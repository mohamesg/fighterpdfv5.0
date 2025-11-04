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

    // التأكد من وجود مفتاح الجهاز
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

    // الحصول على المفتاح العام بصيغة PEM
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

    // تشفير PDF للمشاركة (يرجع 3 ملفات: encrypted, pem, temp decrypted)
    private fun encryptPdfForSharing(pdfPath: String): Map<String, String> {
        // 1. قراءة ملف PDF الأصلي
        val pdfFile = File(pdfPath)
        val pdfBytes = pdfFile.readBytes()

        // 2. توليد مفتاح AES عشوائي
        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(256)
        val aesKey = keyGen.generateKey()

        // 3. توليد IV عشوائي
        val random = SecureRandom()
        val iv = ByteArray(16)
        random.nextBytes(iv)

        // 4. تشفير PDF بـ AES
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, aesKey, IvParameterSpec(iv))
        val encryptedPdfData = cipher.doFinal(pdfBytes)

        // 5. الحصول على المفتاح العام للجهاز
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        val publicKey = keyStore.getCertificate(KEYSTORE_ALIAS).publicKey

        // 6. تشفير مفتاح AES بالمفتاح العام
        val rsaCipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        rsaCipher.init(Cipher.ENCRYPT_MODE, publicKey)
        val wrappedKey = rsaCipher.doFinal(aesKey.encoded)

        // 7. حفظ الملف المشفر في Downloads
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        val fileName = pdfFile.nameWithoutExtension
        val timestamp = System.currentTimeMillis()
        val encryptedFile = File(downloadsDir, "${fileName}_${timestamp}.encryptedpdf")

        FileOutputStream(encryptedFile).use { fos ->
            // كتابة الهيدر
            fos.write("ENCPDF01".toByteArray())
            
            // رقم الإصدار
            fos.write(byteArrayOf(0, 0, 0, 1))
            
            // طول المفتاح المشفر
            val wrappedKeyLength = wrappedKey.size
            fos.write(byteArrayOf(
                (wrappedKeyLength shr 24).toByte(),
                (wrappedKeyLength shr 16).toByte(),
                (wrappedKeyLength shr 8).toByte(),
                wrappedKeyLength.toByte()
            ))
            
            // المفتاح المشفر
            fos.write(wrappedKey)
            
            // حالة الاستخدام (0 = جديد)
            fos.write(0)
            
            // IV
            fos.write(iv)
            
            // البيانات المشفرة
            fos.write(encryptedPdfData)
        }

        // 8. حفظ المفتاح العام في ملف .pem
        val pemFile = File(downloadsDir, "${fileName}_${timestamp}.pem")
        pemFile.writeText(getDevicePublicKeyPem())

        // 9. حفظ نسخة مؤقتة مفكوكة للعرض للمرسل
        val tempDir = cacheDir
        val tempFile = File.createTempFile("temp_view_", ".pdf", tempDir)
        tempFile.writeBytes(pdfBytes)

        return mapOf(
            "encryptedPath" to encryptedFile.absolutePath,
            "pemPath" to pemFile.absolutePath,
            "tempDecryptedPath" to tempFile.absolutePath
        )
    }

    // فك تشفير ملف مستلم
    private fun decryptReceivedPdf(encryptedPath: String, pemPath: String): String {
        val encryptedFile = File(encryptedPath)
        
        FileInputStream(encryptedFile).use { fis ->
            // 1. قراءة الهيدر
            val magic = ByteArray(8)
            fis.read(magic)
            if (String(magic) != "ENCPDF01") {
                throw Exception("تنسيق ملف غير صحيح")
            }

            // 2. قراءة رقم الإصدار
            val version = ByteArray(4)
            fis.read(version)

            // 3. قراءة طول المفتاح المشفر
            val lengthBytes = ByteArray(4)
            fis.read(lengthBytes)
            val wrappedKeyLength = ((lengthBytes[0].toInt() and 0xFF) shl 24) or
                                  ((lengthBytes[1].toInt() and 0xFF) shl 16) or
                                  ((lengthBytes[2].toInt() and 0xFF) shl 8) or
                                  (lengthBytes[3].toInt() and 0xFF)

            // 4. قراءة المفتاح المشفر
            val wrappedKey = ByteArray(wrappedKeyLength)
            fis.read(wrappedKey)

            // 5. قراءة حالة الاستخدام
            val consumedFlag = fis.read()
            if (consumedFlag == 1) {
                throw Exception("هذا الملف تم استخدامه من قبل (استخدام لمرة واحدة)")
            }

            // 6. قراءة IV
            val iv = ByteArray(16)
            fis.read(iv)

            // 7. قراءة البيانات المشفرة
            val encryptedData = fis.readBytes()

            // 8. فك تشفير مفتاح AES باستخدام المفتاح الخاص للجهاز
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

            // 9. فك تشفير البيانات
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(Cipher.DECRYPT_MODE, aesKey, IvParameterSpec(iv))
            val decryptedData = cipher.doFinal(encryptedData)

            // 10. حفظ الملف المفكوك في المجلد المؤقت
            val tempDir = cacheDir
            val tempFile = File.createTempFile("received_", ".pdf", tempDir)
            tempFile.writeBytes(decryptedData)

            // 11. تحديث حالة الاستخدام
            markKeyAsConsumed(encryptedPath, wrappedKeyLength)

            return tempFile.absolutePath
        }
    }

    // تحديث حالة الاستخدام في الملف
    private fun markKeyAsConsumed(encryptedPath: String, wrappedKeyLength: Int) {
        try {
            val file = RandomAccessFile(encryptedPath, "rw")
            file.use {
                // التنقل إلى موضع حالة الاستخدام
                val offset = 8L + 4L + 4L + wrappedKeyLength.toLong()
                it.seek(offset)
                it.write(1) // تحديد أنه تم الاستخدام
            }
        } catch (e: Exception) {
            // في حالة فشل التحديث (مثلاً الملف للقراءة فقط)
            // لا نوقف العملية، لكن نسجل الخطأ
            android.util.Log.w("MainActivity", "فشل تحديث حالة الاستخدام: ${e.message}")
        }
    }
}
