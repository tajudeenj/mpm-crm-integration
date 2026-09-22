import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import java.util.Base64;
import java.util.Scanner;

/**
 * Password Encryption Utility -- ADIB MPM CRM Admin Tool
 * Run this ONCE per environment to encrypt your DB password
 * Store the encrypted value in crm-admin.properties as db.password.enc
 *
 * Compile: javac EncryptPassword.java
 * Run:     java  EncryptPassword
 */
public class EncryptPassword {

    // -- 16 char AES key -- must match key in CrmAdminTool.java
    // -- Never share this key with anyone
    static final String SECRET_KEY = "CrmAdm1nT00lADIB";

    public static void main(String[] args) throws Exception {
        System.out.println("=========================================");
        System.out.println("  CRM Admin Tool -- Password Encryptor  ");
        System.out.println("  ADIB MPM Properties                   ");
        System.out.println("=========================================");
        System.out.println();

        Scanner sc = new Scanner(System.in);
        System.out.print("Enter DB password to encrypt: ");
        String password = sc.nextLine().trim();

        if (password.isEmpty()) {
            System.out.println("ERROR: Password cannot be empty.");
            return;
        }

        // Encrypt
        String encrypted = encrypt(password);

        // Verify -- decrypt and compare
        String decrypted = decrypt(encrypted);
        if (!password.equals(decrypted)) {
            System.out.println("ERROR: Encrypt/decrypt verification failed.");
            return;
        }

        System.out.println();
        System.out.println("=========================================");
        System.out.println("  ENCRYPTED VALUE (copy to properties): ");
        System.out.println("=========================================");
        System.out.println();
        System.out.println("db.password.enc=" + encrypted);
        System.out.println();
        System.out.println("Verification: PASSED");
        System.out.println("Original length : " + password.length());
        System.out.println("Encrypted length: " + encrypted.length());
        System.out.println();
        System.out.println("Steps:");
        System.out.println("1. Copy the db.password.enc line above");
        System.out.println("2. Add it to crm-admin.properties");
        System.out.println("3. Remove or comment out db.password line");
        System.out.println("4. Start CrmAdminTool normally");
        System.out.println("=========================================");
    }

    static String encrypt(String plain) throws Exception {
        Cipher cipher = Cipher.getInstance("AES");
        SecretKeySpec keySpec =
            new SecretKeySpec(SECRET_KEY.getBytes("UTF-8"), "AES");
        cipher.init(Cipher.ENCRYPT_MODE, keySpec);
        byte[] encrypted = cipher.doFinal(
            plain.getBytes("UTF-8"));
        return Base64.getEncoder().encodeToString(encrypted);
    }

    static String decrypt(String encrypted) throws Exception {
        Cipher cipher = Cipher.getInstance("AES");
        SecretKeySpec keySpec =
            new SecretKeySpec(SECRET_KEY.getBytes("UTF-8"), "AES");
        cipher.init(Cipher.DECRYPT_MODE, keySpec);
        byte[] decoded = Base64.getDecoder().decode(encrypted);
        return new String(cipher.doFinal(decoded), "UTF-8");
    }
}
