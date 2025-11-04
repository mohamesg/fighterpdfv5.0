package com.example.fighter_doctors_pdf

import android.os.Bundle
import android.os.Environment
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.*
import java.security.*
import java.util.*
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.fighter_doctors_pdf/crypto"
    private val KEYSTORE_ALIAS = "FighterDoctorsPdfKey"
    private val ANDROID_KEYSTORE = "AndroidKeyStore"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureDeviceKey" -> {
                        try {
                            ensureDeviceKey()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("KEY_ERROR", e.message, null)
                        }
                    }
                    "encryptPdfForSharing" -> {
                        try {
                            val pdfPath = call.argument<String>("pdfPath")!!
                            val encryptionResult = encryptPdfForSharing(pdfPath)
                            result.success(encryptionResult)
                        } catch (e: Exception) {
                            result.error("ENCRYPTION_ERROR", e.message, null)
                        }
                    }
                    "decryptReceivedPdf" -> {
                        try {
                            val encryptedPath = call.argument<String>("encryptedPath")!!
                            val pemPath = call.argument<String>("pemPath")!!
                            val decryptedPath = decryptReceivedPdf(encryptedPath, pemPath)
                            result.success(decryptedPath)
                        } catch (e: Exception) {
                            result.error("DECRYPTION_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Ensure device key exists in Android Keystore
    private fun ensureDeviceKey() {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)

        if (!keyStore.containsAlias(KEYSTORE_ALIAS)) {
            val keyPairGenerator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_RSA,
                ANDROID_KEYSTORE
            )
            
            val spec = KeyGenParameterSpec.Builder(
                KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT
            )
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                .setKeySize(2048)
                .build()

            keyPairGenerator.initialize(spec)
            keyPairGenerator.generateKeyPair()
        }
    }

    // Get device public key in PEM format
    private fun getDevicePublicKeyPem(): String {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        
        val cert = keyStore.getCertificate(KEYSTORE_ALIAS)
        val publicKey = cert.publicKey
        
        val encoded = Base64.getEncoder().encode(publicKey.encoded)
        val pem = StringBuilder()
        pem.append("-----BEGIN PUBLIC KEY-----\n")
        pem.append(String(encoded).chunked(64).joinToString("\n"))
        pem.append("\n-----END PUBLIC KEY-----")
        
        return pem.toString()
    }

    // Encrypt PDF for sharing with optimized performance
    private fun encryptPdfForSharing(pdfPath: String): Map<String, String> {
        val pdfFile = File(pdfPath)
        val pdfBytes = pdfFile.readBytes()

        // Generate random AES key (256-bit for maximum security)
        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(256)
        val aesKey = keyGen.generateKey()

        // Generate random IV (Initialization Vector)
        val random = SecureRandom()
        val iv = ByteArray(16)
        random.nextBytes(iv)

        // Encrypt PDF with AES in CBC mode
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, aesKey, IvParameterSpec(iv))
        val encryptedPdfData = cipher.doFinal(pdfBytes)

        // Get device's public key
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        val publicKey = keyStore.getCertificate(KEYSTORE_ALIAS).publicKey

        // Encrypt AES key with RSA public key
        val rsaCipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        rsaCipher.init(Cipher.ENCRYPT_MODE, publicKey)
        val wrappedKey = rsaCipher.doFinal(aesKey.encoded)

        // Save encrypted PDF file
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        val fileName = pdfFile.nameWithoutExtension
        val timestamp = System.currentTimeMillis()
        val encryptedFile = File(downloadsDir, "${fileName}_${timestamp}.encryptedpdf")

        // Write encrypted file with header
        FileOutputStream(encryptedFile).use { fos ->
            fos.write("ENCPDF01".toByteArray())
            fos.write(byteArrayOf(0, 0, 0, 1))
            
            val wrappedKeyLength = wrappedKey.size
            fos.write(byteArrayOf(
                (wrappedKeyLength shr 24).toByte(),
                (wrappedKeyLength shr 16).toByte(),
                (wrappedKeyLength shr 8).toByte(),
                wrappedKeyLength.toByte()
            ))
            
            fos.write(wrappedKey)
            fos.write(0) // Not consumed flag
            fos.write(iv)
            fos.write(encryptedPdfData)
        }

        // Save public key in PEM format
        val pemFile = File(downloadsDir, "${fileName}_${timestamp}.pem")
        pemFile.writeText(getDevicePublicKeyPem())

        // Create temporary decrypted copy for sender preview
        val tempDir = cacheDir
        val tempFile = File.createTempFile("temp_view_", ".pdf", tempDir)
        tempFile.writeBytes(pdfBytes)

        return mapOf(
            "encryptedPath" to encryptedFile.absolutePath,
            "pemPath" to pemFile.absolutePath,
            "tempDecryptedPath" to tempFile.absolutePath
        )
    }

    // Decrypt received PDF with optimized performance
    private fun decryptReceivedPdf(encryptedPath: String, pemPath: String): String {
        val encryptedFile = File(encryptedPath)
        
        FileInputStream(encryptedFile).use { fis ->
            // Read and validate header
            val magic = ByteArray(8)
            fis.read(magic)
            if (String(magic) != "ENCPDF01") {
                throw Exception("تنسيق ملف غير صحيح")
            }

            // Read version
            val version = ByteArray(4)
            fis.read(version)

            // Read wrapped key length
            val lengthBytes = ByteArray(4)
            fis.read(lengthBytes)
            val wrappedKeyLength = ((lengthBytes[0].toInt() and 0xFF) shl 24) or
                                  ((lengthBytes[1].toInt() and 0xFF) shl 16) or
                                  ((lengthBytes[2].toInt() and 0xFF) shl 8) or
                                  (lengthBytes[3].toInt() and 0xFF)

            // Read wrapped key
            val wrappedKey = ByteArray(wrappedKeyLength)
            fis.read(wrappedKey)

            // Read consumed flag
            val consumedFlag = fis.read()
            if (consumedFlag == 1) {
                throw Exception("هذا الملف تم استخدامه من قبل (استخدام لمرة واحدة)")
            }

            // Read IV
            val iv = ByteArray(16)
            fis.read(iv)

            // Read encrypted data
            val encryptedData = fis.readBytes()

            // Decrypt AES key using device's private key
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
            keyStore.load(null)
            
            if (!keyStore.containsAlias(KEYSTORE_ALIAS)) {
                throw Exception("مفتاح الجهاز غير موجود. تأكد من التهيئة.")
            }
            
            val privateKey = keyStore.getKey(KEYSTORE_ALIAS, null) as PrivateKey

            val rsaCipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            rsaCipher.init(Cipher.DECRYPT_MODE, privateKey)
            val aesKeyBytes = rsaCipher.doFinal(wrappedKey)
            val aesKey = SecretKeySpec(aesKeyBytes, "AES")

            // Decrypt PDF data
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(Cipher.DECRYPT_MODE, aesKey, IvParameterSpec(iv))
            val decryptedData = cipher.doFinal(encryptedData)

            // Save decrypted file to cache
            val tempDir = cacheDir
            val tempFile = File.createTempFile("received_", ".pdf", tempDir)
            tempFile.writeBytes(decryptedData)

            // Mark key as consumed
            markKeyAsConsumed(encryptedPath, wrappedKeyLength)

            return tempFile.absolutePath
        }
    }

    // Mark encrypted file as consumed
    private fun markKeyAsConsumed(encryptedPath: String, wrappedKeyLength: Int) {
        try {
            val file = RandomAccessFile(encryptedPath, "rw")
            file.use {
                val offset = 8L + 4L + 4L + wrappedKeyLength.toLong()
                it.seek(offset)
                it.write(1)
            }
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "فشل تحديث حالة الاستخدام: ${e.message}")
        }
    }
}
