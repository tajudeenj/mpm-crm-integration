import javax.swing.*;
import javax.swing.border.*;
import javax.swing.table.*;
import java.awt.*;
import java.awt.event.*;
import java.io.*;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Types;
import java.util.Properties;
import java.util.Vector;
import java.text.SimpleDateFormat;
import java.util.Date;
import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import java.util.Base64;

/**
 * CRM Integration Admin Tool -- ADIB MPM Properties
 * Complete admin tool for managing CRM integration configuration
 * Java 1.8 compatible
 *
 * Compile: javac -source 8 -target 8 -cp ojdbc8.jar CrmAdminTool.java
 * Run:     java -cp .;ojdbc8.jar CrmAdminTool  (Windows)
 *          java -cp .:ojdbc8.jar CrmAdminTool  (Linux/Mac)
 */
public class CrmAdminTool extends JFrame {

    // -- Config ---------------------------------------------------------------
    private Properties config = new Properties();
    private String dbUrl, dbUser, dbPass;

    // -- Fonts ----------------------------------------------------------------
    static final Font FONT_TITLE  = new Font("Arial", Font.BOLD,  18);
    static final Font FONT_HEADER = new Font("Arial", Font.BOLD,  13);
    static final Font FONT_LABEL  = new Font("Arial", Font.PLAIN, 13);
    static final Font FONT_TABLE  = new Font("Arial", Font.PLAIN, 13);
    static final Font FONT_BTN    = new Font("Arial", Font.BOLD,  13);
    static final Font FONT_STATUS = new Font("Arial", Font.PLAIN, 12);
    static final Font FONT_ITALIC = new Font("Arial", Font.ITALIC,11);

    // -- Colors ---------------------------------------------------------------
    static final Color CLR_BG       = Color.WHITE;
    static final Color CLR_HDR_BG   = new Color(0,   70,  130);
    static final Color CLR_PANEL    = new Color(235, 241, 248);
    static final Color CLR_BORDER   = new Color(160, 185, 210);
    static final Color CLR_TEXT     = new Color(20,  20,  20);
    static final Color CLR_LABEL    = new Color(50,  50,  50);
    static final Color CLR_SUCCESS  = new Color(0,   120, 50);
    static final Color CLR_ERROR    = new Color(180, 0,   0);
    static final Color CLR_WARN     = new Color(150, 90,  0);
    static final Color CLR_INFO     = new Color(0,   80,  160);
    static final Color CLR_ROW_ALT  = new Color(244, 248, 252);
    static final Color CLR_SEL      = new Color(180, 210, 240);
    static final Color BTN_BLUE     = new Color(0,   90,  170);
    static final Color BTN_ORANGE   = new Color(160, 80,  0);
    static final Color BTN_GREEN    = new Color(0,   100, 45);
    static final Color BTN_GREY     = new Color(80,  80,  80);
    static final Color BTN_RED      = new Color(150, 0,   0);
    static final Color BTN_PURPLE   = new Color(100, 0,   150);

    // -- Shared status bar ----------------------------------------------------
    private JLabel lblStatus;
    private JTabbedPane tabs;

    // -- Tab panels -----------------------------------------------------------
    private CredentialTab  tabCredential;
    private RegistryTab    tabRegistry;
    private MappingTab     tabMapping;
    private WatermarkTab   tabWatermark;
    private ErrorCodeTab   tabErrorCode;
    private MonitorTab     tabMonitor;
    private ScriptTab      tabScript;
    private SchedulerTab   tabScheduler;
    private HealthCheckTab tabHealthCheck;
    private TestPushTab    tabTestPush;

    // =========================================================================
    public CrmAdminTool() {
        super("CRM Integration Admin Tool -- ADIB MPM Properties");
        loadConfig();
        buildUI();
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(1350, 800);
        setLocationRelativeTo(null);
        setVisible(true);
        refreshCurrentTab();
    }

    // -- Encryption key -- must match EncryptPassword.java -------------------
    private static final String SECRET_KEY = "CrmAdm1nT00lADIB";

    // -- Load properties ------------------------------------------------------
    private void loadConfig() {
        try (InputStream in = new FileInputStream("crm-admin.properties")) {
            config.load(in);
            dbUrl  = config.getProperty("db.url");
            dbUser = config.getProperty("db.user");

            // Support both plain and encrypted password
            String encPass = config.getProperty("db.password.enc");
            if (encPass != null && !encPass.trim().isEmpty()) {
                // Encrypted password found -- decrypt it
                dbPass = decryptPassword(encPass.trim());
            } else {
                // Plain text password fallback
                dbPass = config.getProperty("db.password");
            }

            if (dbUrl == null || dbUser == null || dbPass == null) {
                JOptionPane.showMessageDialog(null,
                    "crm-admin.properties is missing required fields:\n" +
                    "db.url, db.user, and db.password (or db.password.enc)",
                    "Configuration Error", JOptionPane.ERROR_MESSAGE);
                System.exit(1);
            }
        } catch (IOException e) {
            JOptionPane.showMessageDialog(null,
                "crm-admin.properties not found!\n" +
                "Place it in the same folder as this application.",
                "Configuration Error", JOptionPane.ERROR_MESSAGE);
            System.exit(1);
        }
    }

    // -- Decrypt password from properties file --------------------------------
    private String decryptPassword(String encrypted) {
        try {
            Cipher cipher = Cipher.getInstance("AES");
            SecretKeySpec keySpec = new SecretKeySpec(
                SECRET_KEY.getBytes("UTF-8"), "AES");
            cipher.init(Cipher.DECRYPT_MODE, keySpec);
            byte[] decoded = Base64.getDecoder().decode(encrypted);
            return new String(cipher.doFinal(decoded), "UTF-8");
        } catch (Exception ex) {
            JOptionPane.showMessageDialog(null,
                "Failed to decrypt DB password.\n\n" +
                "Error: " + ex.getMessage() + "\n\n" +
                "Re-run EncryptPassword.java to re-encrypt.",
                "Decrypt Error", JOptionPane.ERROR_MESSAGE);
            System.exit(1);
            return null;
        }
    }

    Connection getConnection() throws SQLException {
        Connection con = DriverManager.getConnection(dbUrl, dbUser, dbPass);
        con.setAutoCommit(false);
        return con;
    }

    String sql(String key) {
        String val = config.getProperty(key);
        if (val == null) {
            JOptionPane.showMessageDialog(this,
                "Query key not found in properties: " + key,
                "Config Error", JOptionPane.ERROR_MESSAGE);
        }
        return val;
    }

    // =========================================================================
    //  UI BUILD
    // =========================================================================
    private void buildUI() {
        getContentPane().setBackground(CLR_BG);
        setLayout(new BorderLayout(0, 0));
        add(buildHeader(),    BorderLayout.NORTH);
        add(buildTabs(),      BorderLayout.CENTER);
        add(buildStatusBar(), BorderLayout.SOUTH);
    }

    private JPanel buildHeader() {
        JPanel p = new JPanel(new BorderLayout());
        p.setBackground(CLR_HDR_BG);
        p.setBorder(new EmptyBorder(12, 20, 12, 20));
        JLabel title = new JLabel(
            "CRM Integration Admin Tool -- ADIB MPM Properties");
        title.setFont(FONT_TITLE);
        title.setForeground(Color.WHITE);

        JPanel right = new JPanel(new FlowLayout(
            FlowLayout.RIGHT, 10, 0));
        right.setBackground(CLR_HDR_BG);

        JButton btnEncUtil = mkBtn("Encrypt Utility", BTN_ORANGE);
        btnEncUtil.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                showEncryptDialog();
            }
        });

        JButton btnViewLog = mkBtn("View Log", BTN_PURPLE);
        btnViewLog.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                showLogViewer();
            }
        });

        JButton btnExit = mkBtn("Exit", BTN_RED);
        btnExit.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                int ok = JOptionPane.showConfirmDialog(
                    null,
                    "Exit CRM Integration Admin Tool?",
                    "Confirm Exit",
                    JOptionPane.YES_NO_OPTION,
                    JOptionPane.QUESTION_MESSAGE);
                if (ok == JOptionPane.YES_OPTION) {
                    LOGGER.log("INFO", "Application exited by user");
                    System.exit(0);
                }
            }
        });

        JLabel sub = new JLabel(
            "Complete Configuration and Monitoring Tool   ");
        sub.setFont(FONT_STATUS);
        sub.setForeground(new Color(200, 220, 240));

        right.add(sub);
        right.add(btnEncUtil);
        right.add(btnViewLog);
        right.add(btnExit);

        p.add(title, BorderLayout.WEST);
        p.add(right, BorderLayout.EAST);
        return p;
    }

    // -- Encrypt Utility Dialog -----------------------------------------------
    private void showEncryptDialog() {
        JDialog dlg = new JDialog(this,
            "Password Encrypt Utility", true);
        dlg.setSize(480, 380);
        dlg.setLocationRelativeTo(this);
        dlg.setResizable(false);
        dlg.getContentPane().setBackground(CLR_BG);
        dlg.setLayout(new BorderLayout(0, 0));

        // -- Header
        JPanel hdr = new JPanel(new BorderLayout());
        hdr.setBackground(CLR_HDR_BG);
        hdr.setBorder(new EmptyBorder(10, 16, 10, 16));
        JLabel title = new JLabel("Password Encrypt Utility");
        title.setFont(FONT_HEADER);
        title.setForeground(Color.WHITE);
        hdr.add(title, BorderLayout.WEST);
        dlg.add(hdr, BorderLayout.NORTH);

        // -- Form
        JPanel form = new JPanel(new GridBagLayout());
        form.setBackground(CLR_PANEL);
        form.setBorder(new EmptyBorder(16, 20, 16, 20));

        GridBagConstraints gc = mkGc();

        // Password fields
        JPasswordField pfPassword = mkPassword(240);
        JPasswordField pfConfirm  = mkPassword(240);

        gc.gridx=0; gc.gridy=0; gc.gridwidth=2;
        JLabel hint1 = new JLabel(
            "Enter the password you want to encrypt:");
        hint1.setFont(FONT_LABEL);
        hint1.setForeground(CLR_LABEL);
        form.add(hint1, gc);
        gc.gridwidth=1;

        addFormRow(form, gc, 1, "Password *",  pfPassword);
        addFormRow(form, gc, 2, "Confirm *",   pfConfirm);

        // Result field
        gc.gridx=0; gc.gridy=3; gc.gridwidth=2;
        gc.insets = new Insets(14, 4, 4, 4);
        JLabel lblResult = new JLabel("Encrypted Value:");
        lblResult.setFont(FONT_LABEL);
        lblResult.setForeground(CLR_LABEL);
        form.add(lblResult, gc);

        gc.gridy=4; gc.insets = new Insets(2, 4, 4, 4);
        JTextField tfResult = mkField(240);
        tfResult.setEditable(false);
        tfResult.setBackground(new Color(230, 240, 250));
        tfResult.setFont(new Font("Courier New", Font.BOLD, 12));
        form.add(tfResult, gc);

        gc.gridy=5; gc.insets = new Insets(2, 4, 4, 4);
        JLabel lblCopyHint = new JLabel(
            "Add to crm-admin.properties as: db.password.enc=<value>");
        lblCopyHint.setFont(FONT_ITALIC);
        lblCopyHint.setForeground(CLR_LABEL);
        form.add(lblCopyHint, gc);

        // Status label
        gc.gridy=6; gc.insets = new Insets(8, 4, 4, 4);
        JLabel lblDlgStatus = new JLabel(" ");
        lblDlgStatus.setFont(FONT_LABEL);
        form.add(lblDlgStatus, gc);

        dlg.add(form, BorderLayout.CENTER);

        // -- Buttons
        JPanel btnPanel = new JPanel(
            new FlowLayout(FlowLayout.CENTER, 12, 10));
        btnPanel.setBackground(CLR_BG);
        btnPanel.setBorder(new MatteBorder(
            1, 0, 0, 0, CLR_BORDER));

        JButton btnEncrypt = mkBtn("Encrypt",          BTN_BLUE);
        JButton btnCopy    = mkBtn("Copy to Clipboard",BTN_GREEN);
        JButton btnClose   = mkBtn("Close",            BTN_GREY);

        btnCopy.setEnabled(false);

        btnEncrypt.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                String pwd1 = new String(
                    pfPassword.getPassword()).trim();
                String pwd2 = new String(
                    pfConfirm.getPassword()).trim();

                if (pwd1.isEmpty()) {
                    lblDlgStatus.setForeground(CLR_ERROR);
                    lblDlgStatus.setText(
                        "Password cannot be empty.");
                    return;
                }
                if (!pwd1.equals(pwd2)) {
                    lblDlgStatus.setForeground(CLR_ERROR);
                    lblDlgStatus.setText(
                        "Passwords do not match.");
                    tfResult.setText("");
                    btnCopy.setEnabled(false);
                    return;
                }

                try {
                    String encrypted = EncryptPassword.encrypt(pwd1);
                    // Verify roundtrip
                    String verify = EncryptPassword.decrypt(encrypted);
                    if (!pwd1.equals(verify)) {
                        lblDlgStatus.setForeground(CLR_ERROR);
                        lblDlgStatus.setText(
                            "Verification failed. Try again.");
                        return;
                    }
                    tfResult.setText(encrypted);
                    btnCopy.setEnabled(true);
                    lblDlgStatus.setForeground(CLR_SUCCESS);
                    lblDlgStatus.setText(
                        "Encrypted successfully. " +
                        "Verification passed.");
                } catch (Exception ex) {
                    lblDlgStatus.setForeground(CLR_ERROR);
                    lblDlgStatus.setText(
                        "Encrypt error: " + ex.getMessage());
                }
            }
        });

        btnCopy.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                String val = tfResult.getText().trim();
                if (!val.isEmpty()) {
                    java.awt.datatransfer.StringSelection ss =
                        new java.awt.datatransfer.StringSelection(
                            "db.password.enc=" + val);
                    java.awt.Toolkit.getDefaultToolkit()
                        .getSystemClipboard().setContents(ss, null);
                    lblDlgStatus.setForeground(CLR_SUCCESS);
                    lblDlgStatus.setText(
                        "Copied to clipboard. " +
                        "Paste into crm-admin.properties.");
                }
            }
        });

        btnClose.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                dlg.dispose();
            }
        });

        btnPanel.add(btnEncrypt);
        btnPanel.add(btnCopy);
        btnPanel.add(btnClose);
        dlg.add(btnPanel, BorderLayout.SOUTH);

        dlg.setVisible(true);
    }

    private JTabbedPane buildTabs() {
        tabs = new JTabbedPane();
        tabs.setFont(FONT_HEADER);
        tabs.setBackground(CLR_BG);

        tabCredential  = new CredentialTab(this);
        tabRegistry    = new RegistryTab(this);
        tabMapping     = new MappingTab(this);
        tabWatermark   = new WatermarkTab(this);
        tabErrorCode   = new ErrorCodeTab(this);
        tabMonitor     = new MonitorTab(this);
        tabScript      = new ScriptTab(this);
        tabScheduler   = new SchedulerTab(this);
        tabHealthCheck = new HealthCheckTab(this);
        tabTestPush    = new TestPushTab(this);

        tabs.addTab("Credentials",     tabCredential);
        tabs.addTab("Service Registry",tabRegistry);
        tabs.addTab("Field Mappings",  tabMapping);
        tabs.addTab("Watermark",       tabWatermark);
        tabs.addTab("Error Codes",     tabErrorCode);
        tabs.addTab("Monitor",         tabMonitor);
        tabs.addTab("Script Download", tabScript);
        tabs.addTab("Scheduler",       tabScheduler);
        tabs.addTab("Health Check",    tabHealthCheck);
        tabs.addTab("Test Push",       tabTestPush);

        tabs.addChangeListener(e -> refreshCurrentTab());
        return tabs;
    }

    private void refreshCurrentTab() {
        int idx = tabs.getSelectedIndex();
        switch (idx) {
            case 0: tabCredential .refresh(); break;
            case 1: tabRegistry   .refresh(); break;
            case 2: tabMapping    .refresh(); break;
            case 3: tabWatermark  .refresh(); break;
            case 4: tabErrorCode  .refresh(); break;
            case 5: tabMonitor    .refresh(); break;
            case 7: tabScheduler  .refresh(); break;
            case 8: tabHealthCheck.refresh(); break;
            case 9: tabTestPush   .refresh(); break;
            default: break;
        }
    }

    private JPanel buildStatusBar() {
        JPanel p = new JPanel(new BorderLayout());
        p.setBackground(CLR_PANEL);
        p.setBorder(new CompoundBorder(
            new MatteBorder(1, 0, 0, 0, CLR_BORDER),
            new EmptyBorder(5, 14, 5, 14)));
        lblStatus = new JLabel("Ready");
        lblStatus.setFont(FONT_STATUS);
        lblStatus.setForeground(CLR_LABEL);
        JLabel ver = new JLabel(
            "ADIB MPM CRM Admin Tool v1.0   ");
        ver.setFont(FONT_STATUS);
        ver.setForeground(new Color(120, 120, 120));
        p.add(lblStatus, BorderLayout.WEST);
        p.add(ver,       BorderLayout.EAST);
        return p;
    }

    // -- Logger ---------------------------------------------------------------
    static final CrmLogger LOGGER = new CrmLogger();

    void setStatus(String msg, Color color) {
        // Determine log level from color
        String level;
        if      (color.equals(CLR_ERROR))   level = "ERROR";
        else if (color.equals(CLR_SUCCESS))  level = "SUCCESS";
        else if (color.equals(CLR_WARN))     level = "WARN";
        else                                 level = "INFO";
        LOGGER.log(level, msg);

        SwingUtilities.invokeLater(new Runnable() {
            public void run() {
                lblStatus.setText(msg);
                lblStatus.setForeground(color);
            }
        });
    }

    void updateTabTitle(int idx, String title) {
        if (tabs != null && idx < tabs.getTabCount())
            tabs.setTitleAt(idx, title);
    }

    // =========================================================================
    //  SQL PREVIEW DIALOG
    //  Call before any DB write -- shows SQL + bind values for review
    //  Returns true if user clicks Execute, false if Cancel
    // =========================================================================
    static boolean showSqlPreview(
            java.awt.Component parent,
            String operationName,
            String sql,
            Object[] params) {

        // Build preview text
        StringBuilder sb = new StringBuilder();
        sb.append("Operation : ").append(operationName).append("\n");
        sb.append(repeatChar('=', 60)).append("\n\n");
        sb.append("SQL:\n");
        sb.append(repeatChar('-', 60)).append("\n");
        // Format SQL nicely
        String formattedSql = sql
            .replace(",", ",\n   ")
            .replace("SET ", "SET\n    ")
            .replace("WHERE ", "\nWHERE ")
            .replace("VALUES", "\nVALUES");
        sb.append(formattedSql);
        sb.append("\n\n");

        if (params != null && params.length > 0) {
            sb.append("Bind Values:\n");
            sb.append(repeatChar('-', 60)).append("\n");
            for (int i = 0; i < params.length; i++) {
                String val = params[i] == null
                    ? "NULL" : params[i].toString();
                // Mask password-like values
                if (val.length() > 30)
                    val = val.substring(0, 30) + "...";
                sb.append(String.format(
                    "  [%2d] %s%n", (i + 1), val));
            }
        }

        sb.append("\n").append(repeatChar('=', 60));
        sb.append("\nReview the SQL above then click Execute to proceed.");

        // Build dialog
        JTextArea ta = new JTextArea(sb.toString());
        ta.setEditable(false);
        ta.setFont(new Font("Courier New", Font.PLAIN, 12));
        ta.setForeground(new Color(20, 20, 20));
        ta.setBackground(new Color(245, 248, 252));
        ta.setLineWrap(false);

        JScrollPane sp = new JScrollPane(ta);
        sp.setPreferredSize(new Dimension(700, 420));

        // Custom buttons
        Object[] options = {"Execute", "Cancel"};
        int choice = JOptionPane.showOptionDialog(
            parent,
            sp,
            "SQL Preview -- " + operationName,
            JOptionPane.YES_NO_OPTION,
            JOptionPane.PLAIN_MESSAGE,
            null,
            options,
            options[1]);  // default = Cancel

        boolean confirmed = (choice == 0);
        if (confirmed) {
            CrmAdminTool.LOGGER.log("INFO",
                "SQL PREVIEW APPROVED: " + operationName);
        } else {
            CrmAdminTool.LOGGER.log("INFO",
                "SQL PREVIEW CANCELLED: " + operationName);
        }
        return confirmed;
    }

    // -- Show Log Viewer ------------------------------------------------------
    void showLogViewer() {
        JDialog dlg = new JDialog(this, "Application Log", false);
        dlg.setSize(900, 500);
        dlg.setLocationRelativeTo(this);
        dlg.getContentPane().setBackground(CLR_BG);
        dlg.setLayout(new BorderLayout(0, 0));

        // Header
        JPanel hdr = new JPanel(new BorderLayout());
        hdr.setBackground(CLR_HDR_BG);
        hdr.setBorder(new EmptyBorder(8, 16, 8, 16));
        JLabel title = new JLabel("Application Log -- crm-admin.log");
        title.setFont(FONT_HEADER);
        title.setForeground(Color.WHITE);
        hdr.add(title, BorderLayout.WEST);
        dlg.add(hdr, BorderLayout.NORTH);

        // Log table
        String[] cols = {"Timestamp", "Level", "Message"};
        DefaultTableModel logModel = new DefaultTableModel(cols, 0) {
            public boolean isCellEditable(int r, int c) { return false; }
        };
        JTable logTable = mkTable(logModel);

        // Color renderer for level column
        logTable.getColumnModel().getColumn(1)
            .setCellRenderer(new DefaultTableCellRenderer() {
            public Component getTableCellRendererComponent(
                    JTable t, Object v, boolean sel,
                    boolean foc, int r, int c) {
                super.getTableCellRendererComponent(
                    t, v, sel, foc, r, c);
                setFont(new Font("Arial", Font.BOLD, 12));
                String val = v == null ? "" : v.toString();
                if      (val.equals("ERROR"))   setForeground(CLR_ERROR);
                else if (val.equals("SUCCESS")) setForeground(CLR_SUCCESS);
                else if (val.equals("WARN"))    setForeground(CLR_WARN);
                else                            setForeground(CLR_INFO);
                setBackground(sel ? CLR_SEL
                    : (r % 2 == 0 ? Color.WHITE : CLR_ROW_ALT));
                setBorder(new EmptyBorder(0, 6, 0, 6));
                return this;
            }
        });

        logTable.getColumnModel().getColumn(0).setPreferredWidth(150);
        logTable.getColumnModel().getColumn(1).setPreferredWidth(70);
        logTable.getColumnModel().getColumn(2).setPreferredWidth(650);

        // Load entries
        java.util.List<String[]> entries = LOGGER.getEntries();
        for (String[] entry : entries) {
            logModel.addRow(entry);
        }
        // Scroll to bottom
        if (logModel.getRowCount() > 0) {
            logTable.scrollRectToVisible(
                logTable.getCellRect(
                    logModel.getRowCount() - 1, 0, true));
        }

        JScrollPane sp = mkScroll(logTable);
        dlg.add(sp, BorderLayout.CENTER);

        // Buttons
        JPanel bot = new JPanel(new FlowLayout(
            FlowLayout.LEFT, 10, 8));
        bot.setBackground(CLR_BG);
        bot.setBorder(new MatteBorder(
            1, 0, 0, 0, CLR_BORDER));

        JButton btnRefresh = mkBtn("Refresh",      BTN_BLUE);
        JButton btnExport  = mkBtn("Export Log",   BTN_GREEN);
        JButton btnClear   = mkBtn("Clear Log",    BTN_RED);
        JButton btnClose   = mkBtn("Close",        BTN_GREY);

        JLabel lblCount = new JLabel(
            "  " + logModel.getRowCount() + " entries");
        lblCount.setFont(FONT_ITALIC);
        lblCount.setForeground(CLR_LABEL);

        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                logModel.setRowCount(0);
                for (String[] entry : LOGGER.getEntries())
                    logModel.addRow(entry);
                lblCount.setText(
                    "  " + logModel.getRowCount() + " entries");
                if (logModel.getRowCount() > 0)
                    logTable.scrollRectToVisible(
                        logTable.getCellRect(
                            logModel.getRowCount()-1, 0, true));
            }
        });

        btnExport.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                JFileChooser fc = new JFileChooser();
                String ts = new SimpleDateFormat("yyyyMMdd_HHmmss")
                    .format(new Date());
                fc.setSelectedFile(
                    new java.io.File("crm-admin-export-" + ts + ".log"));
                if (fc.showSaveDialog(dlg)
                        == JFileChooser.APPROVE_OPTION) {
                    try {
                        LOGGER.exportTo(fc.getSelectedFile());
                        JOptionPane.showMessageDialog(dlg,
                            "Log exported to:\n" +
                            fc.getSelectedFile().getAbsolutePath(),
                            "Export Done",
                            JOptionPane.INFORMATION_MESSAGE);
                    } catch (Exception ex) {
                        JOptionPane.showMessageDialog(dlg,
                            "Export error: " + ex.getMessage(),
                            "Error", JOptionPane.ERROR_MESSAGE);
                    }
                }
            }
        });

        btnClear.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                int ok = JOptionPane.showConfirmDialog(dlg,
                    "Clear all log entries?",
                    "Confirm", JOptionPane.YES_NO_OPTION);
                if (ok == JOptionPane.YES_OPTION) {
                    LOGGER.clear();
                    logModel.setRowCount(0);
                    lblCount.setText("  0 entries");
                }
            }
        });

        btnClose.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                dlg.dispose();
            }
        });

        bot.add(btnRefresh);
        bot.add(btnExport);
        bot.add(btnClear);
        bot.add(btnClose);
        bot.add(lblCount);
        dlg.add(bot, BorderLayout.SOUTH);

        dlg.setVisible(true);
    }

    // =========================================================================
    //  SHARED UI HELPERS
    // =========================================================================
    // -- Java 8 compatible repeat helper -------------------------------------
    static String repeatChar(char c, int count) {
        StringBuilder sb = new StringBuilder(count);
        for (int i = 0; i < count; i++) sb.append(c);
        return sb.toString();
    }

    static JButton mkBtn(String text, Color bg) {
        JButton b = new JButton(text);
        b.setFont(FONT_BTN);
        b.setForeground(Color.WHITE);
        b.setBackground(bg);
        b.setOpaque(true);
        b.setContentAreaFilled(true);
        b.setBorderPainted(true);
        b.setFocusPainted(false);
        b.setBorder(new CompoundBorder(
            new LineBorder(bg.darker(), 1),
            new EmptyBorder(7, 14, 7, 14)));
        b.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        // Force foreground on every paint
        b.addChangeListener(new javax.swing.event.ChangeListener() {
            public void stateChanged(javax.swing.event.ChangeEvent e) {
                b.setForeground(Color.WHITE);
            }
        });
        b.addMouseListener(new MouseAdapter() {
            public void mouseEntered(MouseEvent e) {
                b.setBackground(bg.darker());
                b.setForeground(Color.WHITE);
            }
            public void mouseExited(MouseEvent e) {
                b.setBackground(bg);
                b.setForeground(Color.WHITE);
            }
            public void mousePressed(MouseEvent e) {
                b.setForeground(Color.WHITE);
            }
            public void mouseReleased(MouseEvent e) {
                b.setForeground(Color.WHITE);
            }
        });
        return b;
    }

    static JLabel mkLabel(String text) {
        JLabel l = new JLabel(text);
        l.setFont(FONT_LABEL);
        l.setForeground(CLR_LABEL);
        return l;
    }

    static JTextField mkField(int width) {
        JTextField tf = new JTextField();
        tf.setFont(FONT_LABEL);
        tf.setForeground(CLR_TEXT);
        tf.setBackground(Color.WHITE);
        tf.setPreferredSize(new Dimension(width, 30));
        tf.setBorder(new CompoundBorder(
            new LineBorder(CLR_BORDER, 1),
            new EmptyBorder(3, 6, 3, 6)));
        return tf;
    }

    static JPasswordField mkPassword(int width) {
        JPasswordField pf = new JPasswordField();
        pf.setFont(FONT_LABEL);
        pf.setForeground(CLR_TEXT);
        pf.setBackground(Color.WHITE);
        pf.setPreferredSize(new Dimension(width, 30));
        pf.setBorder(new CompoundBorder(
            new LineBorder(CLR_BORDER, 1),
            new EmptyBorder(3, 6, 3, 6)));
        return pf;
    }

    static JComboBox mkCombo(String[] items) {
        JComboBox cb = new JComboBox(items);
        cb.setFont(FONT_LABEL);
        cb.setBackground(Color.WHITE);
        cb.setForeground(CLR_TEXT);
        return cb;
    }

    static JTable mkTable(DefaultTableModel model) {
        JTable t = new JTable(model);
        t.setBackground(Color.WHITE);
        t.setForeground(CLR_TEXT);
        t.setFont(FONT_TABLE);
        t.setRowHeight(28);
        t.setGridColor(CLR_BORDER);
        t.setSelectionBackground(CLR_SEL);
        t.setSelectionForeground(CLR_TEXT);
        t.setShowVerticalLines(true);
        t.setShowHorizontalLines(true);
        t.setAutoResizeMode(JTable.AUTO_RESIZE_OFF);
        t.getTableHeader().setBackground(new Color(215, 228, 242));
        t.getTableHeader().setForeground(new Color(0, 50, 100));
        t.getTableHeader().setFont(FONT_HEADER);
        t.setDefaultRenderer(Object.class, new AlternatingRenderer());
        return t;
    }

    static JScrollPane mkScroll(JTable t) {
        JScrollPane sp = new JScrollPane(t);
        sp.setBorder(new LineBorder(CLR_BORDER, 1));
        sp.getViewport().setBackground(Color.WHITE);
        return sp;
    }

    static JPanel mkPanel(LayoutManager lm) {
        JPanel p = new JPanel(lm);
        p.setBackground(CLR_BG);
        return p;
    }

    static DefaultTableModel mkModel(String[] cols) {
        return new DefaultTableModel(cols, 0) {
            public boolean isCellEditable(int r, int c) { return false; }
        };
    }

    static JPanel mkFormPanel() {
        JPanel p = new JPanel(new GridBagLayout());
        p.setBackground(CLR_PANEL);
        p.setBorder(new CompoundBorder(
            new LineBorder(CLR_BORDER, 1),
            new EmptyBorder(14, 14, 14, 14)));
        return p;
    }

    static GridBagConstraints mkGc() {
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets  = new Insets(5, 4, 5, 4);
        gc.fill    = GridBagConstraints.HORIZONTAL;
        gc.weightx = 1.0;
        return gc;
    }

    static void addFormRow(JPanel form, GridBagConstraints gc,
                           int row, String label, JComponent field) {
        gc.gridx = 0; gc.gridy = row;
        gc.gridwidth = 1; gc.weightx = 0.3;
        JLabel l = mkLabel(label);
        form.add(l, gc);
        gc.gridx = 1; gc.weightx = 0.7;
        form.add(field, gc);
    }

    static void addSectionLabel(JPanel form, GridBagConstraints gc,
                                int row, String text) {
        gc.gridx = 0; gc.gridy = row;
        gc.gridwidth = 2; gc.weightx = 1.0;
        gc.insets = new Insets(12, 4, 4, 4);
        JLabel l = new JLabel(text);
        l.setFont(FONT_HEADER);
        l.setForeground(CLR_HDR_BG);
        form.add(l, gc);
        gc.gridwidth = 1;
        gc.insets = new Insets(5, 4, 5, 4);
    }

    // =========================================================================
    //  SHARED RENDERERS
    // =========================================================================
    static class AlternatingRenderer extends DefaultTableCellRenderer {
        public Component getTableCellRendererComponent(
                JTable t, Object v, boolean sel,
                boolean foc, int r, int c) {
            super.getTableCellRendererComponent(t, v, sel, foc, r, c);
            setFont(FONT_TABLE);
            setForeground(CLR_TEXT);
            setBackground(sel ? CLR_SEL
                : (r % 2 == 0 ? Color.WHITE : CLR_ROW_ALT));
            setBorder(new EmptyBorder(0, 6, 0, 6));
            return this;
        }
    }

    static class StatusRenderer extends DefaultTableCellRenderer {
        public Component getTableCellRendererComponent(
                JTable t, Object v, boolean sel,
                boolean foc, int r, int c) {
            super.getTableCellRendererComponent(t, v, sel, foc, r, c);
            setFont(new Font("Arial", Font.BOLD, 13));
            String val = v == null ? "" : v.toString();
            if      (val.equals("Y") || val.equals("ACTIVE")
                  || val.equals("SUCCESS") || val.equals("AES256 OK"))
                setForeground(CLR_SUCCESS);
            else if (val.equals("N") || val.equals("EXHAUSTED")
                  || val.equals("Plain Text"))
                setForeground(CLR_ERROR);
            else if (val.equals("SENT") || val.equals("PENDING"))
                setForeground(CLR_INFO);
            else if (val.equals("VALIDATION_FAILED")
                  || val.equals("CRM_REJECTED"))
                setForeground(CLR_WARN);
            else
                setForeground(CLR_TEXT);
            setBackground(sel ? CLR_SEL
                : (r % 2 == 0 ? Color.WHITE : CLR_ROW_ALT));
            setBorder(new EmptyBorder(0, 6, 0, 6));
            return this;
        }
    }

    // =========================================================================
    //  MAIN
    // =========================================================================
    public static void main(String[] args) {
        try {
            Class.forName("oracle.jdbc.OracleDriver");
        } catch (ClassNotFoundException e) {
            JOptionPane.showMessageDialog(null,
                "ojdbc8.jar not found in classpath!\n" +
                "Place ojdbc8.jar in the same folder.",
                "Driver Error", JOptionPane.ERROR_MESSAGE);
            return;
        }
        SwingUtilities.invokeLater(new Runnable() {
            public void run() {
                try {
                    // Use cross-platform LAF -- preserves custom button colors
                    // System LAF on Windows overrides setBackground/setForeground
                    UIManager.setLookAndFeel(
                        UIManager.getCrossPlatformLookAndFeelClassName());
                    // Override default button colors globally
                    UIManager.put("Button.background", new Color(0, 90, 170));
                    UIManager.put("Button.foreground", Color.WHITE);
                    UIManager.put("Button.select",     new Color(0, 60, 120));
                    UIManager.put("Button.focus",      new Color(0, 90, 170));
                    UIManager.put("Panel.background",  Color.WHITE);
                } catch (Exception ignored) {}
                new CrmAdminTool();
            }
        });
    }
}

// =============================================================================
//  TAB 1: CREDENTIALS
// =============================================================================
class CredentialTab extends JPanel {

    private CrmAdminTool app;
    private JTextField     tfCredCode, tfTokenUrl, tfClientId;
    private JTextField     tfWalletPath, tfScope, tfGrantType;
    private JPasswordField pfSecret, pfWalletPwd;
    private JComboBox      cbIsActive;
    private JTable         table;
    private DefaultTableModel model;
    private boolean        isEditMode = false;

    CredentialTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        JSplitPane sp = new JSplitPane(
            JSplitPane.HORIZONTAL_SPLIT,
            buildForm(), buildTable());
        sp.setDividerLocation(380);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        add(sp, BorderLayout.CENTER);
    }

    private JPanel buildForm() {
        JPanel outer = CrmAdminTool.mkPanel(new BorderLayout());
        outer.setBorder(new EmptyBorder(12, 12, 12, 6));

        JPanel form = CrmAdminTool.mkFormPanel();
        GridBagConstraints gc = CrmAdminTool.mkGc();

        CrmAdminTool.addSectionLabel(form, gc, 0, "Credential Details");

        tfCredCode   = CrmAdminTool.mkField(200);
        tfTokenUrl   = CrmAdminTool.mkField(200);
        tfClientId   = CrmAdminTool.mkField(200);
        pfSecret     = CrmAdminTool.mkPassword(200);
        tfScope      = CrmAdminTool.mkField(200);
        tfGrantType  = CrmAdminTool.mkField(200);
        tfGrantType.setText("client_credentials");
        tfWalletPath = CrmAdminTool.mkField(200);
        pfWalletPwd  = CrmAdminTool.mkPassword(200);
        cbIsActive   = CrmAdminTool.mkCombo(new String[]{"Y", "N"});

        CrmAdminTool.addFormRow(form, gc, 1,  "Cred Code *",     tfCredCode);
        CrmAdminTool.addFormRow(form, gc, 2,  "Token URL *",     tfTokenUrl);
        CrmAdminTool.addFormRow(form, gc, 3,  "Client ID *",     tfClientId);
        CrmAdminTool.addFormRow(form, gc, 4,  "Client Secret *", pfSecret);
        CrmAdminTool.addFormRow(form, gc, 5,  "Scope",           tfScope);
        CrmAdminTool.addFormRow(form, gc, 6,  "Grant Type",      tfGrantType);
        CrmAdminTool.addFormRow(form, gc, 7,  "Wallet Path",     tfWalletPath);
        CrmAdminTool.addFormRow(form, gc, 8,  "Wallet Password", pfWalletPwd);
        CrmAdminTool.addFormRow(form, gc, 9,  "Is Active",       cbIsActive);

        gc.gridx = 0; gc.gridy = 10; gc.gridwidth = 2;
        JLabel hint = new JLabel(
            "Client Secret encrypted via AES-256 on save");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        form.add(hint, gc);

        gc.gridy = 11; gc.gridwidth = 2;
        form.add(buildButtons(), gc);

        outer.add(form, BorderLayout.NORTH);
        return outer;
    }

    private JPanel buildButtons() {
        JPanel p = new JPanel(new GridLayout(3, 3, 8, 8));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new EmptyBorder(10, 0, 0, 0));

        JButton btnSave       = CrmAdminTool.mkBtn("Save and Encrypt",    CrmAdminTool.BTN_BLUE);
        JButton btnRefresh    = CrmAdminTool.mkBtn("Refresh List",         CrmAdminTool.BTN_GREY);
        JButton btnRotSec     = CrmAdminTool.mkBtn("Rotate Secret",        CrmAdminTool.BTN_ORANGE);
        JButton btnTestSec    = CrmAdminTool.mkBtn("Test Secret",          CrmAdminTool.BTN_GREEN);
        JButton btnTestWallet = CrmAdminTool.mkBtn("Test Wallet Pwd",      CrmAdminTool.BTN_GREEN);
        JButton btnRotWallet  = CrmAdminTool.mkBtn("Rotate Wallet Pwd",    CrmAdminTool.BTN_ORANGE);
        JButton btnClear      = CrmAdminTool.mkBtn("Clear Form",           CrmAdminTool.BTN_RED);
        JButton btnEdit       = CrmAdminTool.mkBtn("Load Selected",        CrmAdminTool.BTN_GREY);

        btnSave      .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { save(); }
        });
        btnRefresh   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { refresh(); }
        });
        btnRotSec    .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { rotateSecret(); }
        });
        btnTestSec   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { decryptTest("SECRET"); }
        });
        btnTestWallet.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { decryptTest("WALLET"); }
        });
        btnRotWallet .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { rotateWallet(); }
        });
        btnClear     .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { clearForm(); }
        });
        btnEdit      .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadSelected(); }
        });

        p.add(btnSave);       p.add(btnRefresh);    p.add(btnEdit);
        p.add(btnRotSec);     p.add(btnTestSec);    p.add(btnClear);
        p.add(btnRotWallet);  p.add(btnTestWallet);
        return p;
    }

    private JPanel buildTable() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(12, 6, 12, 12));

        JLabel lbl = new JLabel("Stored Credentials");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Cred Code", "Client ID", "Token URL",
            "Active", "Secret Enc", "Updated"
        };
        model = CrmAdminTool.mkModel(cols);
        table = CrmAdminTool.mkTable(model);

        table.getColumnModel().getColumn(3)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());
        table.getColumnModel().getColumn(4)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());

        int[] w = {110, 140, 220, 55, 90, 120};
        for (int i = 0; i < w.length; i++)
            table.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        table.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2) loadSelected();
            }
        });

        p.add(CrmAdminTool.mkScroll(table), BorderLayout.CENTER);

        JLabel hint = new JLabel(
            "  Double-click a row to load into form");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        p.add(hint, BorderLayout.SOUTH);
        return p;
    }

    void refresh() {
        String q = app.sql("query.cred.list");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            model.setRowCount(0);
            while (rs.next()) {
                model.addRow(new Object[]{
                    rs.getString(1), rs.getString(2), rs.getString(3),
                    rs.getString(4), rs.getString(5), rs.getString(6)
                });
            }
            app.setStatus("Credentials loaded: " +
                model.getRowCount(), CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }
    private void save() {
        String credCode  = tfCredCode.getText().trim().toUpperCase();
        String tokenUrl  = tfTokenUrl.getText().trim();
        String clientId  = tfClientId.getText().trim();
        String secret    = new String(pfSecret.getPassword()).trim();
        String scope     = tfScope.getText().trim();
        String grantType = tfGrantType.getText().trim();
        String walletPwd = new String(pfWalletPwd.getPassword()).trim();
        String walletPath= tfWalletPath.getText().trim();
        String isActive  = (String) cbIsActive.getSelectedItem();

        if (credCode.isEmpty() || tokenUrl.isEmpty()
                || clientId.isEmpty() || secret.isEmpty()) {
            app.setStatus(
                "Cred Code, Token URL, Client ID and Secret required.",
                CrmAdminTool.CLR_ERROR);
            return;
        }

        String q = app.sql("query.cred.save");
        if (q == null) return;

        Object[] previewParams = {
            "***SECRET***", credCode, tokenUrl, clientId,
            scope, grantType,
            walletPath.isEmpty() ? null : walletPath,
            walletPwd.isEmpty() ? null : "***WALLET_PWD***",
            isActive
        };
        if (!CrmAdminTool.showSqlPreview(
                this, "Save Credential: " + credCode, q, previewParams))
            return;

        // Replace named binds with positional for Oracle JDBC
        q = q.replaceAll(":secret",     "?")
             .replaceAll(":credcode2",  "?")
             .replaceAll(":credcode",   "?")
             .replaceAll(":tokenurl2",  "?")
             .replaceAll(":tokenurl",   "?")
             .replaceAll(":clientid2",  "?")
             .replaceAll(":clientid",   "?")
             .replaceAll(":scope2",     "?")
             .replaceAll(":scope",      "?")
             .replaceAll(":granttype2", "?")
             .replaceAll(":granttype",  "?")
             .replaceAll(":walletpath2","?")
             .replaceAll(":walletpath", "?")
             .replaceAll(":walletpwd2", "?")
             .replaceAll(":walletpwd",  "?")
             .replaceAll(":isactive2",  "?")
             .replaceAll(":isactive",   "?");

        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(q)) {
            cs.setString(1,  secret);
            cs.setString(2,  credCode);
            cs.setString(3,  tokenUrl);
            cs.setString(4,  clientId);
            cs.setString(5,  scope.isEmpty()      ? null : scope);
            cs.setString(6,  grantType.isEmpty()  ? null : grantType);
            cs.setString(7,  walletPath.isEmpty()  ? null : walletPath);
            cs.setString(8,  walletPwd.isEmpty()   ? null : walletPwd);
            cs.setString(9,  isActive);
            cs.setString(10, credCode);
            cs.setString(11, tokenUrl);
            cs.setString(12, clientId);
            cs.setString(13, scope.isEmpty()      ? null : scope);
            cs.setString(14, grantType.isEmpty()  ? null : grantType);
            cs.setString(15, walletPath.isEmpty()  ? null : walletPath);
            cs.setString(16, walletPwd.isEmpty()   ? null : walletPwd);
            cs.setString(17, isActive);
            cs.execute();
            con.commit();
            app.setStatus(credCode + " saved and encrypted.",
                CrmAdminTool.CLR_SUCCESS);
            clearForm();
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Save error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }
    private void rotateSecret() {
        String credCode = tfCredCode.getText().trim().toUpperCase();
        String secret   = new String(pfSecret.getPassword()).trim();
        if (credCode.isEmpty() || secret.isEmpty()) {
            app.setStatus("Enter Cred Code and new Secret to rotate.",
                CrmAdminTool.CLR_ERROR);
            return;
        }
        int ok = JOptionPane.showConfirmDialog(this,
            "Rotate secret for: " + credCode + "?",
            "Confirm", JOptionPane.YES_NO_OPTION);
        if (ok != JOptionPane.YES_OPTION) return;

        String q = app.sql("query.cred.rotate.secret");
        if (q == null) return;
        // Replace named binds with positional
        q = q.replaceAll(":newval",   "?")
             .replaceAll(":credcode", "?");
        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(q)) {
            cs.setString(1, secret);
            cs.setString(2, credCode);
            cs.execute();
            con.commit();
            app.setStatus("Secret rotated for " + credCode,
                CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Rotate error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void decryptTest(String type) {
        String credCode = tfCredCode.getText().trim().toUpperCase();
        if (credCode.isEmpty()) {
            app.setStatus("Enter Cred Code to test.",
                CrmAdminTool.CLR_ERROR);
            return;
        }

        boolean isWallet = "WALLET".equals(type);
        String queryKey  = isWallet
            ? "query.cred.decrypt.wallet.test"
            : "query.cred.decrypt.test";
        String label     = isWallet ? "Wallet Password" : "Client Secret";

        String q = app.sql(queryKey);
        if (q == null) return;

        // Replace named binds with positional -- Oracle JDBC requirement
        q = q.replaceAll(":credcode", "?")
             .replaceAll(":result",   "?");

        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(q)) {
            cs.setString(1, credCode);
            cs.registerOutParameter(2, Types.VARCHAR);
            cs.execute();
            String result = cs.getString(2);
            JOptionPane.showMessageDialog(this,
                "Credential : " + credCode + "\n" +
                "Field      : " + label    + "\n\n" +
                "Result     : " + result   + "\n\n" +
                "Note: Actual value is never displayed for security.",
                label + " Test -- " + credCode,
                JOptionPane.INFORMATION_MESSAGE);
            app.setStatus(credCode + " " + label + ": " + result,
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Test error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void rotateWallet() {
        String credCode  = tfCredCode.getText().trim().toUpperCase();
        String walletPwd = new String(pfWalletPwd.getPassword()).trim();
        if (credCode.isEmpty() || walletPwd.isEmpty()) {
            app.setStatus(
                "Enter Cred Code and new Wallet Password to rotate.",
                CrmAdminTool.CLR_ERROR);
            return;
        }
        int ok = JOptionPane.showConfirmDialog(this,
            "Rotate Wallet Password for: " + credCode + "?\n" +
            "This will overwrite the existing wallet password.",
            "Confirm Rotation",
            JOptionPane.YES_NO_OPTION,
            JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;

        String q = app.sql("query.cred.rotate.wallet");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, walletPwd);
            ps.setString(2, credCode);
            ps.executeUpdate();
            con.commit();
            app.setStatus("Wallet password updated for " + credCode,
                CrmAdminTool.CLR_SUCCESS);
            pfWalletPwd.setText("");
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Rotate wallet error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadSelected() {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a row first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String credCode = (String) model.getValueAt(row, 0);
        String q = app.sql("query.cred.load.single");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, credCode);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                tfCredCode   .setText(rs.getString(1));
                tfTokenUrl   .setText(rs.getString(2));
                tfClientId   .setText(rs.getString(3));
                pfSecret     .setText("");
                pfWalletPwd  .setText("");
                tfScope      .setText(rs.getString(4) == null ? "" : rs.getString(4));
                tfGrantType  .setText(rs.getString(5) == null ? "" : rs.getString(5));
                tfWalletPath .setText(rs.getString(6) == null ? "" : rs.getString(6));
                cbIsActive   .setSelectedItem(rs.getString(7));
                app.setStatus("Loaded " + credCode +
                    " -- enter new secret to rotate.",
                    CrmAdminTool.CLR_LABEL);
            }
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void clearForm() {
        tfCredCode   .setText("");
        tfTokenUrl   .setText("");
        tfClientId   .setText("");
        pfSecret     .setText("");
        pfWalletPwd  .setText("");
        tfScope      .setText("");
        tfGrantType  .setText("client_credentials");
        tfWalletPath .setText("");
        cbIsActive   .setSelectedIndex(0);
    }
}

// =============================================================================
//  TAB 2: SERVICE REGISTRY
// =============================================================================
class RegistryTab extends JPanel {

    private CrmAdminTool app;
    private JTextField   tfServiceName, tfEntityName, tfSourceView;
    private JTextField   tfSourceProc, tfSourceFilterCol, tfSourceKeyCol;
    private JTextField   tfJsonMappingName;
    private JTextField   tfRecordTypeHdr, tfEventCodeHdr;
    private JTextField   tfApicEndpointUrl, tfHttpMethod, tfApicApiVersion;
    private JTextField   tfCallbackTargetTable, tfCallbackKeyCol;
    private JTextField   tfCallbackStatusCol, tfCallbackRefCol;
    private JTextField   tfPostCallbackProc;
    private JTextField   tfExecOrder, tfBatchSize;
    private JTextField   tfMaxRetry, tfRetryInterval, tfTimeoutMins;
    private JComboBox    cbOperationType, cbSourceType;
    private JComboBox    cbIsActive, cbCredCode;
    private JTable       table;
    private DefaultTableModel model;

    RegistryTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        JSplitPane sp = new JSplitPane(
            JSplitPane.HORIZONTAL_SPLIT,
            buildForm(), buildTable());
        sp.setDividerLocation(420);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        add(sp, BorderLayout.CENTER);
    }

    private JPanel buildForm() {
        JPanel outer = CrmAdminTool.mkPanel(new BorderLayout());
        outer.setBorder(new EmptyBorder(12, 12, 12, 6));

        JScrollPane scroll = new JScrollPane(buildFormInner());
        scroll.setBorder(null);
        scroll.getViewport().setBackground(CrmAdminTool.CLR_BG);
        outer.add(scroll, BorderLayout.CENTER);
        return outer;
    }

    private JPanel buildFormInner() {
        JPanel form = CrmAdminTool.mkFormPanel();
        GridBagConstraints gc = CrmAdminTool.mkGc();

        CrmAdminTool.addSectionLabel(form, gc, 0, "Service Details");

        tfServiceName       = CrmAdminTool.mkField(200);
        tfEntityName        = CrmAdminTool.mkField(200);
        cbOperationType     = CrmAdminTool.mkCombo(
            new String[]{"CREATE","UPDATE","DELETE","BATCH"});
        cbSourceType        = CrmAdminTool.mkCombo(
            new String[]{"VIEW","PROCEDURE","BATCH"});
        tfSourceView        = CrmAdminTool.mkField(200);
        tfSourceProc        = CrmAdminTool.mkField(200);
        tfSourceFilterCol   = CrmAdminTool.mkField(200);
        tfSourceKeyCol      = CrmAdminTool.mkField(200);
        tfJsonMappingName   = CrmAdminTool.mkField(200);
        tfRecordTypeHdr     = CrmAdminTool.mkField(200);
        tfEventCodeHdr      = CrmAdminTool.mkField(200);
        tfApicEndpointUrl   = CrmAdminTool.mkField(200);
        tfHttpMethod        = CrmAdminTool.mkField(200);
        tfApicApiVersion    = CrmAdminTool.mkField(200);
        tfCallbackTargetTable= CrmAdminTool.mkField(200);
        tfCallbackKeyCol    = CrmAdminTool.mkField(200);
        tfCallbackStatusCol = CrmAdminTool.mkField(200);
        tfCallbackRefCol    = CrmAdminTool.mkField(200);
        tfPostCallbackProc  = CrmAdminTool.mkField(200);
        cbCredCode          = new JComboBox();
        cbCredCode.setFont(CrmAdminTool.FONT_LABEL);
        cbCredCode.setBackground(Color.WHITE);
        tfExecOrder         = CrmAdminTool.mkField(80);
        tfBatchSize         = CrmAdminTool.mkField(80);
        tfMaxRetry          = CrmAdminTool.mkField(80);
        tfRetryInterval     = CrmAdminTool.mkField(80);
        tfTimeoutMins       = CrmAdminTool.mkField(80);
        cbIsActive          = CrmAdminTool.mkCombo(new String[]{"Y","N"});

        // -- Section: Basic
        CrmAdminTool.addFormRow(form, gc, 1,  "Service Name *",       tfServiceName);
        CrmAdminTool.addFormRow(form, gc, 2,  "Entity Name",          tfEntityName);
        CrmAdminTool.addFormRow(form, gc, 3,  "Operation Type",       cbOperationType);
        CrmAdminTool.addFormRow(form, gc, 4,  "Source Type",          cbSourceType);
        CrmAdminTool.addFormRow(form, gc, 5,  "Source View",          tfSourceView);
        CrmAdminTool.addFormRow(form, gc, 6,  "Source Procedure",     tfSourceProc);
        CrmAdminTool.addFormRow(form, gc, 7,  "Filter Column",        tfSourceFilterCol);
        CrmAdminTool.addFormRow(form, gc, 8,  "Key Column",           tfSourceKeyCol);
        CrmAdminTool.addFormRow(form, gc, 9,  "JSON Mapping Name",    tfJsonMappingName);

        // -- Section: APIC
        gc.gridx=0; gc.gridy=10; gc.gridwidth=2;
        CrmAdminTool.addSectionLabel(form, gc, 10, "APIC Headers");
        CrmAdminTool.addFormRow(form, gc, 11, "Record Type Header",   tfRecordTypeHdr);
        CrmAdminTool.addFormRow(form, gc, 12, "Event Code Header",    tfEventCodeHdr);
        CrmAdminTool.addFormRow(form, gc, 13, "APIC Endpoint URL",    tfApicEndpointUrl);
        CrmAdminTool.addFormRow(form, gc, 14, "HTTP Method",          tfHttpMethod);
        CrmAdminTool.addFormRow(form, gc, 15, "APIC API Version",     tfApicApiVersion);

        // -- Section: Callback
        gc.gridx=0; gc.gridy=16; gc.gridwidth=2;
        CrmAdminTool.addSectionLabel(form, gc, 16, "Callback Settings");
        CrmAdminTool.addFormRow(form, gc, 17, "Callback Table",       tfCallbackTargetTable);
        CrmAdminTool.addFormRow(form, gc, 18, "Callback Key Col",     tfCallbackKeyCol);
        CrmAdminTool.addFormRow(form, gc, 19, "Callback Status Col",  tfCallbackStatusCol);
        CrmAdminTool.addFormRow(form, gc, 20, "Callback Ref Col",     tfCallbackRefCol);
        CrmAdminTool.addFormRow(form, gc, 21, "Post Callback Proc",   tfPostCallbackProc);

        // -- Section: Settings
        gc.gridx=0; gc.gridy=22; gc.gridwidth=2;
        CrmAdminTool.addSectionLabel(form, gc, 22, "Job Settings");
        CrmAdminTool.addFormRow(form, gc, 23, "Cred Code",            cbCredCode);
        CrmAdminTool.addFormRow(form, gc, 24, "Execution Order",      tfExecOrder);
        CrmAdminTool.addFormRow(form, gc, 25, "Batch Size",           tfBatchSize);
        CrmAdminTool.addFormRow(form, gc, 26, "Max Retry Count",      tfMaxRetry);
        CrmAdminTool.addFormRow(form, gc, 27, "Retry Interval (min)", tfRetryInterval);
        CrmAdminTool.addFormRow(form, gc, 28, "Timeout (min)",        tfTimeoutMins);
        CrmAdminTool.addFormRow(form, gc, 29, "Is Active",            cbIsActive);

        gc.gridx = 0; gc.gridy = 30; gc.gridwidth = 2;
        form.add(buildButtons(), gc);

        return form;
    }


    private JPanel buildButtons() {
        JPanel p = new JPanel(new GridLayout(3, 3, 8, 8));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new EmptyBorder(10, 0, 0, 0));

        JButton btnWizard   = CrmAdminTool.mkBtn("+ New Service Wizard", new Color(31,56,100));
        JButton btnSave     = CrmAdminTool.mkBtn("Save Service",    CrmAdminTool.BTN_BLUE);
        JButton btnRefresh  = CrmAdminTool.mkBtn("Refresh List",    CrmAdminTool.BTN_GREY);
        JButton btnEnable   = CrmAdminTool.mkBtn("Enable",          CrmAdminTool.BTN_GREEN);
        JButton btnDisable  = CrmAdminTool.mkBtn("Disable",         CrmAdminTool.BTN_RED);
        JButton btnLoad     = CrmAdminTool.mkBtn("Load Selected",   CrmAdminTool.BTN_GREY);
        JButton btnClear    = CrmAdminTool.mkBtn("Clear Form",      CrmAdminTool.BTN_GREY);

        btnWizard .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { openWizard(); }
        });
        btnSave   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { save(); }
        });
        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { refresh(); }
        });
        btnEnable .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { setActive("Y"); }
        });
        btnDisable.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { setActive("N"); }
        });
        btnLoad   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadSelected(); }
        });
        btnClear  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { clearForm(); }
        });

        p.add(btnWizard);  p.add(btnSave);    p.add(btnRefresh);
        p.add(btnLoad);    p.add(btnEnable);  p.add(btnDisable);
        p.add(btnClear);
        return p;
    }

    // ── New Service Wizard ────────────────────────────────────────────────────
    private void openWizard() {
        JDialog dlg = new JDialog(
            (Frame) SwingUtilities.getWindowAncestor(this),
            "New Service Wizard", true);
        dlg.setSize(680, 620);
        dlg.setLocationRelativeTo(this);
        dlg.getContentPane().setBackground(CrmAdminTool.CLR_BG);
        dlg.setLayout(new BorderLayout());

        // Step tracker panel (top)
        String[] stepNames = {
            "1. Service Registry",
            "2. Field Mappings",
            "3. Watermark Init",
            "4. Scheduler Job"
        };
        final int[] currentStep = {0};
        JPanel stepBar = new JPanel(new GridLayout(1, 4, 4, 0));
        stepBar.setBackground(CrmAdminTool.CLR_BG);
        stepBar.setBorder(new EmptyBorder(12, 12, 8, 12));
        JLabel[] stepLabels = new JLabel[4];
        for (int i = 0; i < 4; i++) {
            stepLabels[i] = new JLabel(stepNames[i], JLabel.CENTER);
            stepLabels[i].setFont(CrmAdminTool.FONT_LABEL);
            stepLabels[i].setOpaque(true);
            stepLabels[i].setBorder(
                BorderFactory.createCompoundBorder(
                    BorderFactory.createLineBorder(CrmAdminTool.CLR_BORDER),
                    BorderFactory.createEmptyBorder(6, 4, 6, 4)));
            stepLabels[i].setBackground(CrmAdminTool.CLR_PANEL);
            stepLabels[i].setForeground(CrmAdminTool.CLR_LABEL);
            stepBar.add(stepLabels[i]);
        }
        dlg.add(stepBar, BorderLayout.NORTH);

        // Cards panel
        JPanel cards = new JPanel(new CardLayout());
        cards.setBackground(CrmAdminTool.CLR_BG);

        // ── STEP 1: Registry ──────────────────────────────────────────────────
        JPanel step1 = new JPanel(new BorderLayout());
        step1.setBackground(CrmAdminTool.CLR_BG);
        step1.setBorder(new EmptyBorder(0, 12, 4, 12));

        JLabel s1Title = new JLabel("Step 1: Service Registry — Core Configuration");
        s1Title.setFont(CrmAdminTool.FONT_HEADER);
        s1Title.setForeground(CrmAdminTool.CLR_HDR_BG);
        s1Title.setBorder(new EmptyBorder(0, 0, 8, 0));

        JPanel s1Form = new JPanel(new GridBagLayout());
        s1Form.setBackground(CrmAdminTool.CLR_PANEL);
        s1Form.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(CrmAdminTool.CLR_BORDER),
            BorderFactory.createEmptyBorder(12, 14, 12, 14)));
        GridBagConstraints gc1 = CrmAdminTool.mkGc();

        JTextField w_svcName    = CrmAdminTool.mkField(220);
        JTextField w_entityName = CrmAdminTool.mkField(220);
        JComboBox  w_opType     = CrmAdminTool.mkCombo(
            new String[]{"CREATE","UPDATE","DELETE","BATCH"});
        JComboBox  w_srcType    = CrmAdminTool.mkCombo(
            new String[]{"VIEW","PROCEDURE","BATCH"});
        JTextField w_srcView    = CrmAdminTool.mkField(220);
        JTextField w_srcKey     = CrmAdminTool.mkField(220);
        JTextField w_jsonMap    = CrmAdminTool.mkField(220);
        JTextField w_apicUrl    = CrmAdminTool.mkField(220);
        JTextField w_recTypeHdr = CrmAdminTool.mkField(220);
        JTextField w_eventHdr   = CrmAdminTool.mkField(220);
        JTextField w_execOrder  = CrmAdminTool.mkField(60);
        w_execOrder.setText("10");
        JTextField w_maxRetry   = CrmAdminTool.mkField(60);
        w_maxRetry.setText("3");
        JTextField w_retryInt   = CrmAdminTool.mkField(60);
        w_retryInt.setText("30");
        JComboBox  w_credCode   = new JComboBox();
        w_credCode.setFont(CrmAdminTool.FONT_LABEL);
        w_credCode.setBackground(Color.WHITE);

        // Load cred codes
        try (Connection con = app.getConnection()) {
            String q2 = app.sql("query.cred.codes");
            if (q2 != null) {
                try (PreparedStatement ps2 = con.prepareStatement(q2);
                     ResultSet rs2 = ps2.executeQuery()) {
                    while (rs2.next())
                        w_credCode.addItem(rs2.getString(1));
                }
            }
        } catch (Exception ex) { /* silent */ }

        CrmAdminTool.addFormRow(s1Form, gc1, 0,  "Service Name *",     w_svcName);
        CrmAdminTool.addFormRow(s1Form, gc1, 1,  "Entity Name *",      w_entityName);
        CrmAdminTool.addFormRow(s1Form, gc1, 2,  "Operation Type",     w_opType);
        CrmAdminTool.addFormRow(s1Form, gc1, 3,  "Source Type",        w_srcType);
        CrmAdminTool.addFormRow(s1Form, gc1, 4,  "Source View/Proc *", w_srcView);
        CrmAdminTool.addFormRow(s1Form, gc1, 5,  "Key Column *",       w_srcKey);
        CrmAdminTool.addFormRow(s1Form, gc1, 6,  "JSON Mapping Name *",w_jsonMap);
        CrmAdminTool.addFormRow(s1Form, gc1, 7,  "APIC Endpoint URL *",w_apicUrl);
        CrmAdminTool.addFormRow(s1Form, gc1, 8,  "Record Type Header", w_recTypeHdr);
        CrmAdminTool.addFormRow(s1Form, gc1, 9,  "Event Code Header",  w_eventHdr);
        CrmAdminTool.addFormRow(s1Form, gc1, 10, "Cred Code",          w_credCode);
        CrmAdminTool.addFormRow(s1Form, gc1, 11, "Execution Order",    w_execOrder);
        CrmAdminTool.addFormRow(s1Form, gc1, 12, "Max Retry",          w_maxRetry);
        CrmAdminTool.addFormRow(s1Form, gc1, 13, "Retry Interval(min)",w_retryInt);

        JScrollPane s1Scroll = new JScrollPane(s1Form);
        s1Scroll.setBorder(null);

        step1.add(s1Title,  BorderLayout.NORTH);
        step1.add(s1Scroll, BorderLayout.CENTER);

        // ── STEP 2: Field Mappings ────────────────────────────────────────────
        JPanel step2 = new JPanel(new BorderLayout());
        step2.setBackground(CrmAdminTool.CLR_BG);
        step2.setBorder(new EmptyBorder(0, 12, 4, 12));

        JLabel s2Title = new JLabel("Step 2: Field Mappings — Define JSON fields");
        s2Title.setFont(CrmAdminTool.FONT_HEADER);
        s2Title.setForeground(CrmAdminTool.CLR_HDR_BG);
        s2Title.setBorder(new EmptyBorder(0, 0, 8, 0));

        JLabel s2Hint = new JLabel(
            "<html><b>JSON Mapping Name</b> will be auto-filled from Step 1.<br>" +
            "Add one row per field. Use the Field Mappings tab for full editing.<br>" +
            "Or click <b>Skip</b> — add mappings later in Field Mappings tab.</html>");
        s2Hint.setFont(CrmAdminTool.FONT_ITALIC);
        s2Hint.setForeground(CrmAdminTool.CLR_LABEL);
        s2Hint.setBorder(new EmptyBorder(4, 0, 10, 0));

        // Quick mapping entry table
        String[] mapCols = {"Source Column","JSON Path","Data Type","Mandatory","Order"};
        DefaultTableModel mapModel = new DefaultTableModel(mapCols, 0) {
            public boolean isCellEditable(int r, int c) { return true; }
        };
        // Pre-add 5 empty rows
        for (int i = 0; i < 8; i++)
            mapModel.addRow(new Object[]{"","","VARCHAR2","Y",String.valueOf((i+1)*10)});
        JTable mapTable = new JTable(mapModel);
        mapTable.setFont(CrmAdminTool.FONT_LABEL);
        mapTable.setRowHeight(24);
        mapTable.getColumnModel().getColumn(2).setCellEditor(
            new DefaultCellEditor(CrmAdminTool.mkCombo(
                new String[]{"VARCHAR2","NUMBER","DATE","BOOLEAN","CLOB"})));
        mapTable.getColumnModel().getColumn(3).setCellEditor(
            new DefaultCellEditor(CrmAdminTool.mkCombo(new String[]{"Y","N"})));
        mapTable.getColumnModel().getColumn(0).setPreferredWidth(140);
        mapTable.getColumnModel().getColumn(1).setPreferredWidth(140);
        mapTable.getColumnModel().getColumn(4).setPreferredWidth(50);

        JPanel s2BtnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 6, 4));
        s2BtnRow.setBackground(CrmAdminTool.CLR_BG);
        JButton btnAddRow = CrmAdminTool.mkBtn("+ Add Row", CrmAdminTool.BTN_BLUE);
        JButton btnDelRow = CrmAdminTool.mkBtn("- Remove Row", CrmAdminTool.BTN_RED);
        btnAddRow.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                mapModel.addRow(new Object[]{"","","VARCHAR2","Y",
                    String.valueOf((mapModel.getRowCount()+1)*10)});
            }
        });
        btnDelRow.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                int sel = mapTable.getSelectedRow();
                if (sel >= 0) mapModel.removeRow(sel);
            }
        });
        s2BtnRow.add(btnAddRow); s2BtnRow.add(btnDelRow);

        JPanel s2Top = new JPanel(new BorderLayout());
        s2Top.setBackground(CrmAdminTool.CLR_BG);
        s2Top.add(s2Title,  BorderLayout.NORTH);
        s2Top.add(s2Hint,   BorderLayout.CENTER);
        s2Top.add(s2BtnRow, BorderLayout.SOUTH);

        step2.add(s2Top, BorderLayout.NORTH);
        step2.add(new JScrollPane(mapTable), BorderLayout.CENTER);

        // ── STEP 3: Watermark Init ────────────────────────────────────────────
        JPanel step3 = new JPanel(new BorderLayout());
        step3.setBackground(CrmAdminTool.CLR_BG);
        step3.setBorder(new EmptyBorder(0, 12, 4, 12));

        JLabel s3Title = new JLabel("Step 3: Watermark Initialisation");
        s3Title.setFont(CrmAdminTool.FONT_HEADER);
        s3Title.setForeground(CrmAdminTool.CLR_HDR_BG);
        s3Title.setBorder(new EmptyBorder(0, 0, 8, 0));

        JTextArea s3Info = new JTextArea();
        s3Info.setFont(CrmAdminTool.FONT_LABEL);
        s3Info.setEditable(false);
        s3Info.setBackground(new Color(240, 248, 255));
        s3Info.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(CrmAdminTool.CLR_BORDER),
            BorderFactory.createEmptyBorder(10, 12, 10, 12)));
        s3Info.setText(
            "A watermark record will be created for this service in\n" +
            "CRM_MPM_API_WATERMARK.\n\n" +
            "This tracks the last processed timestamp so the outbound\n" +
            "job only picks up NEW records on each run.\n\n" +
            "Initial watermark date: Will be set to SYSDATE - 1 day\n" +
            "(picks up all records from yesterday onwards on first run).\n\n" +
            "Click 'Set Custom Start Date' to specify a different start\n" +
            "date (e.g. if you want to push all historical records).");

        JPanel s3DateRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 8));
        s3DateRow.setBackground(CrmAdminTool.CLR_BG);
        JLabel s3DtLbl = new JLabel("Custom Start Date (DD-MON-YY):");
        s3DtLbl.setFont(CrmAdminTool.FONT_LABEL);
        JTextField w_watermarkDate = CrmAdminTool.mkField(120);
        w_watermarkDate.setToolTipText("Leave blank = SYSDATE-1 (yesterday)");
        JLabel s3DtHint = new JLabel("  leave blank = yesterday");
        s3DtHint.setFont(CrmAdminTool.FONT_ITALIC);
        s3DtHint.setForeground(CrmAdminTool.CLR_LABEL);
        s3DateRow.add(s3DtLbl); s3DateRow.add(w_watermarkDate); s3DateRow.add(s3DtHint);

        step3.add(s3Title,  BorderLayout.NORTH);
        step3.add(s3Info,   BorderLayout.CENTER);
        step3.add(s3DateRow,BorderLayout.SOUTH);

        // ── STEP 4: Scheduler Job ─────────────────────────────────────────────
        JPanel step4 = new JPanel(new BorderLayout());
        step4.setBackground(CrmAdminTool.CLR_BG);
        step4.setBorder(new EmptyBorder(0, 12, 4, 12));

        JLabel s4Title = new JLabel("Step 4: Scheduler Job (Optional)");
        s4Title.setFont(CrmAdminTool.FONT_HEADER);
        s4Title.setForeground(CrmAdminTool.CLR_HDR_BG);
        s4Title.setBorder(new EmptyBorder(0, 0, 8, 0));

        JLabel s4Hint = new JLabel(
            "<html>If this new service needs its OWN dedicated job, configure below.<br>" +
            "If it will be picked up by an existing outbound job — click <b>Skip / Finish</b>.</html>");
        s4Hint.setFont(CrmAdminTool.FONT_ITALIC);
        s4Hint.setForeground(CrmAdminTool.CLR_LABEL);
        s4Hint.setBorder(new EmptyBorder(4, 0, 10, 0));

        JPanel s4Form = new JPanel(new GridBagLayout());
        s4Form.setBackground(CrmAdminTool.CLR_PANEL);
        s4Form.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(CrmAdminTool.CLR_BORDER),
            BorderFactory.createEmptyBorder(12, 14, 12, 14)));
        GridBagConstraints gc4 = CrmAdminTool.mkGc();

        JTextField w_jobName     = CrmAdminTool.mkField(220);
        JTextField w_jobInterval = CrmAdminTool.mkField(220);
        w_jobInterval.setText("FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0");
        w_jobInterval.setToolTipText("e.g. FREQ=DAILY;BYHOUR=6 or FREQ=MINUTELY;INTERVAL=30");
        JTextField w_jobProc     = CrmAdminTool.mkField(220);
        w_jobProc.setText("PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB");
        JComboBox  w_jobEnabled  = CrmAdminTool.mkCombo(new String[]{"Y","N"});
        JTextField w_jobComment  = CrmAdminTool.mkField(220);

        CrmAdminTool.addFormRow(s4Form, gc4, 0, "Job Name",         w_jobName);
        CrmAdminTool.addFormRow(s4Form, gc4, 1, "Repeat Interval",  w_jobInterval);
        CrmAdminTool.addFormRow(s4Form, gc4, 2, "Procedure to Call",w_jobProc);
        CrmAdminTool.addFormRow(s4Form, gc4, 3, "Enable on Create", w_jobEnabled);
        CrmAdminTool.addFormRow(s4Form, gc4, 4, "Comment",          w_jobComment);

        JPanel s4Note = new JPanel(new BorderLayout());
        s4Note.setBackground(new Color(230, 244, 255));
        s4Note.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(new Color(180, 210, 240)),
            BorderFactory.createEmptyBorder(8, 10, 8, 10)));
        JLabel s4NoteText = new JLabel(
            "<html><b>Note:</b> Most new services do NOT need a new job.<br>" +
            "The existing CRM_MPM_OUTBOUND jobs pick up all active registry entries.<br>" +
            "Only add a job if this service needs a different schedule.</html>");
        s4NoteText.setFont(CrmAdminTool.FONT_ITALIC);
        s4NoteText.setForeground(new Color(31, 56, 100));
        s4Note.add(s4NoteText);

        JPanel s4Top = new JPanel(new BorderLayout(0, 8));
        s4Top.setBackground(CrmAdminTool.CLR_BG);
        s4Top.add(s4Title, BorderLayout.NORTH);
        s4Top.add(s4Hint,  BorderLayout.CENTER);
        s4Top.add(s4Note,  BorderLayout.SOUTH);

        step4.add(s4Top,  BorderLayout.NORTH);
        step4.add(s4Form, BorderLayout.CENTER);

        // ── Cards ─────────────────────────────────────────────────────────────
        cards.add(step1, "1");
        cards.add(step2, "2");
        cards.add(step3, "3");
        cards.add(step4, "4");

        // ── Navigation buttons ────────────────────────────────────────────────
        JPanel navPanel = new JPanel(new BorderLayout());
        navPanel.setBackground(CrmAdminTool.CLR_BG);
        navPanel.setBorder(new EmptyBorder(8, 12, 12, 12));

        JLabel stepInfo = new JLabel("Step 1 of 4 — Service Registry");
        stepInfo.setFont(CrmAdminTool.FONT_LABEL);
        stepInfo.setForeground(CrmAdminTool.CLR_LABEL);

        JPanel navBtns = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        navBtns.setBackground(CrmAdminTool.CLR_BG);
        JButton btnBack   = CrmAdminTool.mkBtn("< Back",        CrmAdminTool.BTN_GREY);
        JButton btnNext   = CrmAdminTool.mkBtn("Next >",        CrmAdminTool.BTN_BLUE);
        JButton btnSkip   = CrmAdminTool.mkBtn("Skip / Finish", CrmAdminTool.BTN_GREEN);
        JButton btnCancel = CrmAdminTool.mkBtn("Cancel",        CrmAdminTool.BTN_RED);
        btnBack.setEnabled(false);

        String[] stepInfoText = {
            "Step 1 of 4 — Service Registry",
            "Step 2 of 4 — Field Mappings",
            "Step 3 of 4 — Watermark Init",
            "Step 4 of 4 — Scheduler Job"
        };

        // Highlight current step
        Runnable updateStepBar = new Runnable() {
            public void run() {
                int s = currentStep[0];
                for (int i = 0; i < 4; i++) {
                    if (i < s) {
                        stepLabels[i].setBackground(new Color(55, 86, 35));
                        stepLabels[i].setForeground(Color.WHITE);
                    } else if (i == s) {
                        stepLabels[i].setBackground(new Color(31, 56, 100));
                        stepLabels[i].setForeground(Color.WHITE);
                    } else {
                        stepLabels[i].setBackground(CrmAdminTool.CLR_PANEL);
                        stepLabels[i].setForeground(CrmAdminTool.CLR_LABEL);
                    }
                }
                stepInfo.setText(stepInfoText[s]);
                btnBack.setEnabled(s > 0);
                btnNext.setEnabled(s < 3);
                ((CardLayout) cards.getLayout()).show(cards, String.valueOf(s + 1));
            }
        };
        updateStepBar.run();

        btnBack.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                if (currentStep[0] > 0) {
                    currentStep[0]--;
                    updateStepBar.run();
                }
            }
        });

        btnNext.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                // Validate before proceeding
                if (currentStep[0] == 0) {
                    if (w_svcName.getText().trim().isEmpty()) {
                        JOptionPane.showMessageDialog(dlg,
                            "Service Name is required.", "Validation",
                            JOptionPane.WARNING_MESSAGE); return;
                    }
                    if (w_apicUrl.getText().trim().isEmpty()) {
                        JOptionPane.showMessageDialog(dlg,
                            "APIC Endpoint URL is required.", "Validation",
                            JOptionPane.WARNING_MESSAGE); return;
                    }
                    // Auto-fill job name in step 4
                    w_jobName.setText("CRM_MPM_" +
                        w_svcName.getText().trim().toUpperCase()
                        .replaceAll("[^A-Z0-9_]","_") + "_JOB");
                    w_jobComment.setText("Outbound job for " +
                        w_svcName.getText().trim());
                }
                if (currentStep[0] == 1) {
                    // Stop table editing before moving on
                    if (mapTable.isEditing())
                        mapTable.getCellEditor().stopCellEditing();
                }
                if (currentStep[0] < 3) {
                    currentStep[0]++;
                    updateStepBar.run();
                }
            }
        });

        // Skip / Finish — save whatever steps are done
        btnSkip.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                if (mapTable.isEditing())
                    mapTable.getCellEditor().stopCellEditing();
                saveWizard(dlg,
                    w_svcName, w_entityName, w_opType, w_srcType,
                    w_srcView, w_srcKey, w_jsonMap, w_apicUrl,
                    w_recTypeHdr, w_eventHdr, w_credCode,
                    w_execOrder, w_maxRetry, w_retryInt,
                    mapModel, w_watermarkDate,
                    w_jobName, w_jobInterval, w_jobProc,
                    w_jobEnabled, w_jobComment,
                    currentStep[0]);
            }
        });

        btnCancel.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { dlg.dispose(); }
        });

        navBtns.add(btnCancel); navBtns.add(btnBack);
        navBtns.add(btnNext);   navBtns.add(btnSkip);
        navPanel.add(stepInfo, BorderLayout.WEST);
        navPanel.add(navBtns,  BorderLayout.EAST);

        dlg.add(cards,    BorderLayout.CENTER);
        dlg.add(navPanel, BorderLayout.SOUTH);
        dlg.setVisible(true);
    }

    private void saveWizard(
            JDialog dlg,
            JTextField w_svcName, JTextField w_entityName,
            JComboBox  w_opType,  JComboBox  w_srcType,
            JTextField w_srcView, JTextField w_srcKey,
            JTextField w_jsonMap, JTextField w_apicUrl,
            JTextField w_recTypeHdr, JTextField w_eventHdr,
            JComboBox  w_credCode,
            JTextField w_execOrder, JTextField w_maxRetry,
            JTextField w_retryInt,
            DefaultTableModel mapModel,
            JTextField w_watermarkDate,
            JTextField w_jobName, JTextField w_jobInterval,
            JTextField w_jobProc, JComboBox  w_jobEnabled,
            JTextField w_jobComment,
            int lastStep) {

        String svcName = w_svcName.getText().trim();
        if (svcName.isEmpty()) {
            JOptionPane.showMessageDialog(dlg,
                "Service Name is required before saving.",
                "Validation", JOptionPane.WARNING_MESSAGE);
            return;
        }

        StringBuilder summary = new StringBuilder();
        int saved = 0; int errors = 0;

        try (Connection con = app.getConnection()) {

            // ── Step 1: Registry ──────────────────────────────────────────────
            String qReg = app.sql("query.registry.save");
            if (qReg != null) {
                try (PreparedStatement ps = con.prepareStatement(
                        qReg.replaceAll(":[a-z_]+","?"))) {
                    int p = 1;
                    ps.setString(p++, svcName);
                    ps.setString(p++, w_entityName.getText().trim());
                    ps.setString(p++, (String) w_opType.getSelectedItem());
                    ps.setString(p++, (String) w_srcType.getSelectedItem());
                    ps.setString(p++, w_srcView.getText().trim());
                    ps.setString(p++, w_srcView.getText().trim()); // proc same field
                    ps.setString(p++, "");  // filter col
                    ps.setString(p++, w_srcKey.getText().trim());
                    ps.setString(p++, w_jsonMap.getText().trim());
                    ps.setString(p++, w_recTypeHdr.getText().trim());
                    ps.setString(p++, w_eventHdr.getText().trim());
                    ps.setString(p++, w_apicUrl.getText().trim());
                    ps.setString(p++, "POST");
                    ps.setString(p++, "");  // api version
                    ps.setString(p++, "");  // cb table
                    ps.setString(p++, "");  // cb key col
                    ps.setString(p++, "");  // cb status col
                    ps.setString(p++, "");  // cb ref col
                    ps.setString(p++, "");  // post cb proc
                    ps.setString(p++, w_credCode.getSelectedItem() != null
                        ? (String) w_credCode.getSelectedItem() : "");
                    ps.setString(p++, w_execOrder.getText().trim().isEmpty() ? "10"
                        : w_execOrder.getText().trim());
                    ps.setString(p++, "100"); // batch size
                    ps.setString(p++, w_maxRetry.getText().trim().isEmpty() ? "3"
                        : w_maxRetry.getText().trim());
                    ps.setString(p++, w_retryInt.getText().trim().isEmpty() ? "30"
                        : w_retryInt.getText().trim());
                    ps.setString(p++, "60"); // timeout
                    ps.setString(p++, "Y");
                    // update params (same order again for MERGE)
                    ps.setString(p++, w_entityName.getText().trim());
                    ps.setString(p++, (String) w_opType.getSelectedItem());
                    ps.setString(p++, (String) w_srcType.getSelectedItem());
                    ps.setString(p++, w_srcView.getText().trim());
                    ps.setString(p++, w_srcView.getText().trim());
                    ps.setString(p++, "");
                    ps.setString(p++, w_srcKey.getText().trim());
                    ps.setString(p++, w_jsonMap.getText().trim());
                    ps.setString(p++, w_recTypeHdr.getText().trim());
                    ps.setString(p++, w_eventHdr.getText().trim());
                    ps.setString(p++, w_apicUrl.getText().trim());
                    ps.setString(p++, "POST");
                    ps.setString(p++, "");
                    ps.setString(p++, "");
                    ps.setString(p++, "");
                    ps.setString(p++, "");
                    ps.setString(p++, "");
                    ps.setString(p++, "");
                    ps.setString(p++, w_credCode.getSelectedItem() != null
                        ? (String) w_credCode.getSelectedItem() : "");
                    ps.setString(p++, w_execOrder.getText().trim().isEmpty() ? "10"
                        : w_execOrder.getText().trim());
                    ps.setString(p++, "100");
                    ps.setString(p++, w_maxRetry.getText().trim().isEmpty() ? "3"
                        : w_maxRetry.getText().trim());
                    ps.setString(p++, w_retryInt.getText().trim().isEmpty() ? "30"
                        : w_retryInt.getText().trim());
                    ps.setString(p++, "60");
                    ps.executeUpdate();
                    saved++;
                    summary.append("[OK] Registry: ").append(svcName)
                        .append(" saved.\n");
                }
            }

            // ── Step 2: Field Mappings ────────────────────────────────────────
            String qMap = app.sql("query.mapping.save");
            if (qMap != null && lastStep >= 1) {
                String jsonMapName = w_jsonMap.getText().trim();
                int mapSaved = 0;
                for (int r = 0; r < mapModel.getRowCount(); r++) {
                    String srcCol  = (String) mapModel.getValueAt(r, 0);
                    String jPath   = (String) mapModel.getValueAt(r, 1);
                    String dtype   = (String) mapModel.getValueAt(r, 2);
                    String mand    = (String) mapModel.getValueAt(r, 3);
                    String ord     = (String) mapModel.getValueAt(r, 4);
                    if (srcCol == null || srcCol.trim().isEmpty()) continue;
                    if (jPath == null || jPath.trim().isEmpty()) continue;
                    try (PreparedStatement ps = con.prepareStatement(
                            qMap.replaceAll(":[a-z_]+","?"))) {
                        ps.setString(1, jsonMapName);
                        ps.setString(2, srcCol.trim());
                        ps.setString(3, jPath.trim());
                        ps.setString(4, dtype != null ? dtype : "VARCHAR2");
                        ps.setString(5, "");  // date format
                        ps.setString(6, mand != null ? mand : "Y");
                        ps.setString(7, ord != null && !ord.trim().isEmpty()
                            ? ord.trim() : String.valueOf((r+1)*10));
                        ps.setString(8, "Y");
                        // update part
                        ps.setString(9,  jPath.trim());
                        ps.setString(10, dtype != null ? dtype : "VARCHAR2");
                        ps.setString(11, "");
                        ps.setString(12, mand != null ? mand : "Y");
                        ps.setString(13, ord != null && !ord.trim().isEmpty()
                            ? ord.trim() : String.valueOf((r+1)*10));
                        ps.setString(14, "Y");
                        ps.executeUpdate();
                        mapSaved++;
                    }
                }
                if (mapSaved > 0) {
                    saved++;
                    summary.append("[OK] Field Mappings: ").append(mapSaved)
                        .append(" field(s) saved for ").append(jsonMapName)
                        .append(".\n");
                } else {
                    summary.append("[SKIP] Field Mappings: skipped (no rows filled).\n");
                }
            } else {
                summary.append("[SKIP] Field Mappings: skipped.\n");
            }

            // ── Step 3: Watermark ─────────────────────────────────────────────
            if (lastStep >= 2) {
                String wDate = w_watermarkDate.getText().trim();
                String wmSql = "MERGE INTO CRM_MPM_API_WATERMARK W " +
                    "USING (SELECT REGISTRY_ID FROM CRM_MPM_API_REGISTRY " +
                    "WHERE SERVICE_NAME=?) R ON (W.REGISTRY_ID=R.REGISTRY_ID) " +
                    "WHEN NOT MATCHED THEN INSERT (REGISTRY_ID,LAST_PROCESSED_TS," +
                    "LAST_RUN_STATUS,UPDATED_DATE) VALUES (R.REGISTRY_ID," +
                    (wDate.isEmpty()
                        ? "SYSDATE-1"
                        : "TO_DATE(?,'DD-MON-YY')")
                    + ",'INIT',SYSDATE)";
                try (PreparedStatement ps = con.prepareStatement(wmSql)) {
                    ps.setString(1, svcName);
                    if (!wDate.isEmpty()) ps.setString(2, wDate);
                    ps.executeUpdate();
                    saved++;
                    summary.append("[OK] Watermark: initialised for ").append(svcName)
                        .append(wDate.isEmpty() ? " (from yesterday)" : " (from "+wDate+")")
                        .append(".\n");
                }
            } else {
                summary.append("[SKIP] Watermark: skipped.\n");
            }

            // ── Step 4: Scheduler Job ─────────────────────────────────────────
            String jobName = w_jobName.getText().trim();
            if (lastStep >= 3 && !jobName.isEmpty()) {
                String jobSql =
                    "BEGIN\n" +
                    "  DBMS_SCHEDULER.CREATE_JOB(\n" +
                    "    job_name        => ?,\n" +
                    "    job_type        => 'STORED_PROCEDURE',\n" +
                    "    job_action      => ?,\n" +
                    "    repeat_interval => ?,\n" +
                    "    enabled         => " +
                    ("Y".equals(w_jobEnabled.getSelectedItem()) ? "TRUE" : "FALSE") +
                    ",\n" +
                    "    comments        => ?\n" +
                    "  );\n" +
                    "END;";
                try (CallableStatement cs = con.prepareCall(jobSql)) {
                    cs.setString(1, jobName);
                    cs.setString(2, w_jobProc.getText().trim());
                    cs.setString(3, w_jobInterval.getText().trim());
                    cs.setString(4, w_jobComment.getText().trim());
                    cs.execute();
                    saved++;
                    summary.append("[OK] Scheduler Job: ").append(jobName)
                        .append(" created.\n");
                } catch (Exception ex) {
                    errors++;
                    summary.append("[WARN] Scheduler Job: ").append(ex.getMessage())
                        .append("\n(Job may already exist — check Scheduler tab)\n");
                }
            } else {
                summary.append("[SKIP] Scheduler Job: skipped.\n");
            }

            con.commit();

        } catch (Exception ex) {
            app.setStatus("Wizard error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
            JOptionPane.showMessageDialog(dlg,
                "Error during save:\n" + ex.getMessage(),
                "Wizard Error", JOptionPane.ERROR_MESSAGE);
            return;
        }

        // ── Summary dialog ────────────────────────────────────────────────────
        summary.append("\n").append(saved).append(" step(s) completed.");
        if (errors > 0)
            summary.append("\n").append(errors).append(" warning(s) — check above.");

        JOptionPane.showMessageDialog(dlg,
            summary.toString(),
            "New Service Wizard — Complete",
            errors > 0 ? JOptionPane.WARNING_MESSAGE
                       : JOptionPane.INFORMATION_MESSAGE);

        app.setStatus("New service '" + svcName + "' onboarded via wizard.",
            CrmAdminTool.CLR_SUCCESS);
        dlg.dispose();
        refresh();
    }

    private JPanel buildTable() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(12, 6, 12, 12));

        JLabel lbl = new JLabel("Registered Services");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Service Name", "Entity", "Op Type", "Source Type",
            "Source View", "Source Proc", "Filter Col", "Key Col",
            "JSON Mapping", "Record Type Hdr", "Event Code Hdr",
            "APIC URL", "Method", "API Version",
            "Callback Table", "CB Key Col", "CB Status Col",
            "CB Ref Col", "Post CB Proc",
            "Cred Code", "Exec Order", "Batch",
            "Max Retry", "Retry Interval", "Timeout", "Active"
        };
        model = CrmAdminTool.mkModel(cols);
        table = CrmAdminTool.mkTable(model);

        table.getColumnModel().getColumn(25)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());

        int[] w = {160,90,70,80,160,120,110,100,
                   130,120,110,200,70,90,
                   130,90,100,90,120,
                   80,70,55,70,100,65,55};
        for (int i = 0; i < w.length; i++)
            table.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        table.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2) loadSelected();
            }
        });

        p.add(CrmAdminTool.mkScroll(table), BorderLayout.CENTER);

        JLabel hint = new JLabel(
            "  Double-click a row to edit");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        p.add(hint, BorderLayout.SOUTH);
        return p;
    }

    void refresh() {
        loadCredCodes();
        String q = app.sql("query.registry.list");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            model.setRowCount(0);
            while (rs.next()) {
                model.addRow(new Object[]{
                    rs.getString(1),  rs.getString(2),
                    rs.getString(3),  rs.getString(4),
                    rs.getString(5),  rs.getString(6),
                    rs.getString(7),  rs.getString(8),
                    rs.getString(9),  rs.getString(10),
                    rs.getString(11), rs.getString(12),
                    rs.getString(13), rs.getString(14),
                    rs.getString(15), rs.getString(16),
                    rs.getString(17), rs.getString(18),
                    rs.getString(19), rs.getString(20),
                    rs.getString(21), rs.getString(22),
                    rs.getString(23), rs.getString(24),
                    rs.getString(25), rs.getString(26)
                });
            }
            app.updateTabTitle(1,
                "Service Registry (" + model.getRowCount() + ")");
            app.setStatus("Services loaded: " + model.getRowCount(),
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadCredCodes() {
        String q = app.sql("query.cred.codes");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            cbCredCode.removeAllItems();
            cbCredCode.addItem("-- Select --");
            while (rs.next()) cbCredCode.addItem(rs.getString(1));
        } catch (SQLException ex) {
            app.setStatus("Cred codes load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void save() {
        String svcName = tfServiceName.getText().trim().toUpperCase();
        if (svcName.isEmpty()) {
            app.setStatus("Service Name is required.",
                CrmAdminTool.CLR_ERROR);
            return;
        }

        String credCode = (String) cbCredCode.getSelectedItem();
        if (credCode != null && credCode.startsWith("--"))
            credCode = null;

        String q = app.sql("query.registry.save");
        if (q == null) return;

        // Show SQL preview before executing
        Object[] previewParams = {
            svcName,
            tfEntityName.getText().trim(),
            cbOperationType.getSelectedItem(),
            cbSourceType.getSelectedItem(),
            tfSourceView.getText().trim(),
            tfSourceProc.getText().trim(),
            tfSourceFilterCol.getText().trim(),
            tfSourceKeyCol.getText().trim(),
            tfJsonMappingName.getText().trim(),
            tfRecordTypeHdr.getText().trim(),
            tfEventCodeHdr.getText().trim(),
            tfApicEndpointUrl.getText().trim(),
            tfHttpMethod.getText().trim(),
            tfApicApiVersion.getText().trim(),
            tfCallbackTargetTable.getText().trim(),
            cbIsActive.getSelectedItem(),
            tfExecOrder.getText().trim()
        };
        if (!CrmAdminTool.showSqlPreview(
                this, "Save Service: " + svcName, q, previewParams))
            return;

        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            // MERGE ON condition
            ps.setString(1,  svcName);
            // UPDATE SET
            ps.setString(2,  tfEntityName.getText().trim());
            ps.setString(3,  (String)cbOperationType.getSelectedItem());
            ps.setString(4,  (String)cbSourceType.getSelectedItem());
            ps.setString(5,  tfSourceView.getText().trim().isEmpty()
                ? null : tfSourceView.getText().trim());
            ps.setString(6,  tfSourceProc.getText().trim().isEmpty()
                ? null : tfSourceProc.getText().trim());
            ps.setString(7,  tfSourceFilterCol.getText().trim().isEmpty()
                ? null : tfSourceFilterCol.getText().trim());
            ps.setString(8,  tfSourceKeyCol.getText().trim().isEmpty()
                ? null : tfSourceKeyCol.getText().trim());
            ps.setString(9,  tfJsonMappingName.getText().trim().isEmpty()
                ? null : tfJsonMappingName.getText().trim());
            ps.setString(10, tfRecordTypeHdr.getText().trim().isEmpty()
                ? null : tfRecordTypeHdr.getText().trim());
            ps.setString(11, tfEventCodeHdr.getText().trim().isEmpty()
                ? null : tfEventCodeHdr.getText().trim());
            ps.setString(12, tfApicEndpointUrl.getText().trim().isEmpty()
                ? null : tfApicEndpointUrl.getText().trim());
            ps.setString(13, tfHttpMethod.getText().trim().isEmpty()
                ? null : tfHttpMethod.getText().trim());
            ps.setString(14, tfApicApiVersion.getText().trim().isEmpty()
                ? null : tfApicApiVersion.getText().trim());
            ps.setString(15, tfCallbackTargetTable.getText().trim().isEmpty()
                ? null : tfCallbackTargetTable.getText().trim());
            ps.setString(16, tfCallbackKeyCol.getText().trim().isEmpty()
                ? null : tfCallbackKeyCol.getText().trim());
            ps.setString(17, tfCallbackStatusCol.getText().trim().isEmpty()
                ? null : tfCallbackStatusCol.getText().trim());
            ps.setString(18, tfCallbackRefCol.getText().trim().isEmpty()
                ? null : tfCallbackRefCol.getText().trim());
            ps.setString(19, tfPostCallbackProc.getText().trim().isEmpty()
                ? null : tfPostCallbackProc.getText().trim());
            ps.setString(20, credCode);
            ps.setString(21, tfExecOrder.getText().trim().isEmpty()
                ? "99" : tfExecOrder.getText().trim());
            ps.setString(22, tfBatchSize.getText().trim().isEmpty()
                ? "100" : tfBatchSize.getText().trim());
            ps.setString(23, tfMaxRetry.getText().trim().isEmpty()
                ? "3" : tfMaxRetry.getText().trim());
            ps.setString(24, tfRetryInterval.getText().trim().isEmpty()
                ? "30" : tfRetryInterval.getText().trim());
            ps.setString(25, tfTimeoutMins.getText().trim().isEmpty()
                ? "60" : tfTimeoutMins.getText().trim());
            ps.setString(26, (String)cbIsActive.getSelectedItem());
            // INSERT VALUES -- repeat all
            ps.setString(27, svcName);
            ps.setString(28, tfEntityName.getText().trim());
            ps.setString(29, (String)cbOperationType.getSelectedItem());
            ps.setString(30, (String)cbSourceType.getSelectedItem());
            ps.setString(31, tfSourceView.getText().trim().isEmpty()
                ? null : tfSourceView.getText().trim());
            ps.setString(32, tfSourceProc.getText().trim().isEmpty()
                ? null : tfSourceProc.getText().trim());
            ps.setString(33, tfSourceFilterCol.getText().trim().isEmpty()
                ? null : tfSourceFilterCol.getText().trim());
            ps.setString(34, tfSourceKeyCol.getText().trim().isEmpty()
                ? null : tfSourceKeyCol.getText().trim());
            ps.setString(35, tfJsonMappingName.getText().trim().isEmpty()
                ? null : tfJsonMappingName.getText().trim());
            ps.setString(36, tfRecordTypeHdr.getText().trim().isEmpty()
                ? null : tfRecordTypeHdr.getText().trim());
            ps.setString(37, tfEventCodeHdr.getText().trim().isEmpty()
                ? null : tfEventCodeHdr.getText().trim());
            ps.setString(38, tfApicEndpointUrl.getText().trim().isEmpty()
                ? null : tfApicEndpointUrl.getText().trim());
            ps.setString(39, tfHttpMethod.getText().trim().isEmpty()
                ? null : tfHttpMethod.getText().trim());
            ps.setString(40, tfApicApiVersion.getText().trim().isEmpty()
                ? null : tfApicApiVersion.getText().trim());
            ps.setString(41, tfCallbackTargetTable.getText().trim().isEmpty()
                ? null : tfCallbackTargetTable.getText().trim());
            ps.setString(42, tfCallbackKeyCol.getText().trim().isEmpty()
                ? null : tfCallbackKeyCol.getText().trim());
            ps.setString(43, tfCallbackStatusCol.getText().trim().isEmpty()
                ? null : tfCallbackStatusCol.getText().trim());
            ps.setString(44, tfCallbackRefCol.getText().trim().isEmpty()
                ? null : tfCallbackRefCol.getText().trim());
            ps.setString(45, tfPostCallbackProc.getText().trim().isEmpty()
                ? null : tfPostCallbackProc.getText().trim());
            ps.setString(46, credCode);
            ps.setString(47, tfExecOrder.getText().trim().isEmpty()
                ? "99" : tfExecOrder.getText().trim());
            ps.setString(48, tfBatchSize.getText().trim().isEmpty()
                ? "100" : tfBatchSize.getText().trim());
            ps.setString(49, tfMaxRetry.getText().trim().isEmpty()
                ? "3" : tfMaxRetry.getText().trim());
            ps.setString(50, tfRetryInterval.getText().trim().isEmpty()
                ? "30" : tfRetryInterval.getText().trim());
            ps.setString(51, tfTimeoutMins.getText().trim().isEmpty()
                ? "60" : tfTimeoutMins.getText().trim());
            ps.setString(52, (String)cbIsActive.getSelectedItem());

            ps.executeUpdate();
            con.commit();
            app.setStatus("Service " + svcName + " saved.",
                CrmAdminTool.CLR_SUCCESS);
            clearForm();
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Save error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void setActive(String flag) {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a service first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String svcName = (String) model.getValueAt(row, 0);
        String q = app.sql("query.registry.set.active");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, flag);
            ps.setString(2, svcName);
            ps.executeUpdate();
            con.commit();
            app.setStatus(svcName + " set to " +
                ("Y".equals(flag) ? "ACTIVE" : "INACTIVE"),
                CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Update error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadSelected() {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a row first.", CrmAdminTool.CLR_WARN);
            return;
        }
        tfServiceName        .setText(str(model.getValueAt(row, 0)));
        tfEntityName         .setText(str(model.getValueAt(row, 1)));
        cbOperationType      .setSelectedItem(str(model.getValueAt(row, 2)));
        cbSourceType         .setSelectedItem(str(model.getValueAt(row, 3)));
        tfSourceView         .setText(str(model.getValueAt(row, 4)));
        tfSourceProc         .setText(str(model.getValueAt(row, 5)));
        tfSourceFilterCol    .setText(str(model.getValueAt(row, 6)));
        tfSourceKeyCol       .setText(str(model.getValueAt(row, 7)));
        tfJsonMappingName    .setText(str(model.getValueAt(row, 8)));
        tfRecordTypeHdr      .setText(str(model.getValueAt(row, 9)));
        tfEventCodeHdr       .setText(str(model.getValueAt(row, 10)));
        tfApicEndpointUrl    .setText(str(model.getValueAt(row, 11)));
        tfHttpMethod         .setText(str(model.getValueAt(row, 12)));
        tfApicApiVersion     .setText(str(model.getValueAt(row, 13)));
        tfCallbackTargetTable.setText(str(model.getValueAt(row, 14)));
        tfCallbackKeyCol     .setText(str(model.getValueAt(row, 15)));
        tfCallbackStatusCol  .setText(str(model.getValueAt(row, 16)));
        tfCallbackRefCol     .setText(str(model.getValueAt(row, 17)));
        tfPostCallbackProc   .setText(str(model.getValueAt(row, 18)));
        cbCredCode           .setSelectedItem(str(model.getValueAt(row, 19)));
        tfExecOrder          .setText(str(model.getValueAt(row, 20)));
        tfBatchSize          .setText(str(model.getValueAt(row, 21)));
        tfMaxRetry           .setText(str(model.getValueAt(row, 22)));
        tfRetryInterval      .setText(str(model.getValueAt(row, 23)));
        tfTimeoutMins        .setText(str(model.getValueAt(row, 24)));
        cbIsActive           .setSelectedItem(str(model.getValueAt(row, 25)));
        app.setStatus("Loaded " + str(model.getValueAt(row, 0)),
            CrmAdminTool.CLR_LABEL);
    }

    private void clearForm() {
        tfServiceName.setText("");        tfEntityName.setText("");
        tfSourceView.setText("");         tfSourceProc.setText("");
        tfSourceFilterCol.setText("");    tfSourceKeyCol.setText("");
        tfJsonMappingName.setText("");
        tfRecordTypeHdr.setText("");      tfEventCodeHdr.setText("");
        tfApicEndpointUrl.setText("");    tfHttpMethod.setText("");
        tfApicApiVersion.setText("");
        tfCallbackTargetTable.setText(""); tfCallbackKeyCol.setText("");
        tfCallbackStatusCol.setText("");  tfCallbackRefCol.setText("");
        tfPostCallbackProc.setText("");
        tfExecOrder.setText("99");        tfBatchSize.setText("100");
        tfMaxRetry.setText("3");          tfRetryInterval.setText("30");
        tfTimeoutMins.setText("60");
        cbOperationType.setSelectedIndex(0);
        cbSourceType.setSelectedIndex(0);
        cbIsActive.setSelectedIndex(0);
    }

    private String str(Object o) {
        return o == null ? "" : o.toString();
    }
}

// =============================================================================
//  TAB 3: FIELD MAPPINGS
// =============================================================================
class MappingTab extends JPanel {

    private CrmAdminTool app;
    private JComboBox    cbService;
    private JTextField   tfSourceCol, tfJsonField, tfDateFormat, tfFieldOrder;
    private JComboBox    cbDataType, cbIsActive, cbIsMandatory;
    private JTable       table;
    private DefaultTableModel model;

    MappingTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        JSplitPane sp = new JSplitPane(
            JSplitPane.HORIZONTAL_SPLIT,
            buildForm(), buildTable());
        sp.setDividerLocation(360);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        add(sp, BorderLayout.CENTER);
    }

    private JPanel buildForm() {
        JPanel outer = CrmAdminTool.mkPanel(new BorderLayout());
        outer.setBorder(new EmptyBorder(12, 12, 12, 6));

        JPanel form = CrmAdminTool.mkFormPanel();
        GridBagConstraints gc = CrmAdminTool.mkGc();

        CrmAdminTool.addSectionLabel(form, gc, 0, "Field Mapping");

        cbService    = new JComboBox();
        cbService.setFont(CrmAdminTool.FONT_LABEL);
        cbService.setBackground(Color.WHITE);
        cbService.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadMappings(); }
        });

        tfFieldOrder  = CrmAdminTool.mkField(80);
        tfSourceCol   = CrmAdminTool.mkField(200);
        tfJsonField   = CrmAdminTool.mkField(200);
        cbDataType    = CrmAdminTool.mkCombo(
            new String[]{"STRING","NUMBER","DATE","BOOLEAN"});
        tfDateFormat  = CrmAdminTool.mkField(200);
        cbIsMandatory = CrmAdminTool.mkCombo(new String[]{"N","Y"});
        cbIsActive    = CrmAdminTool.mkCombo(new String[]{"Y","N"});

        cbDataType.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                tfDateFormat.setEnabled(
                    "DATE".equals(cbDataType.getSelectedItem()));
            }
        });

        CrmAdminTool.addFormRow(form, gc, 1, "Service *",        cbService);
        CrmAdminTool.addFormRow(form, gc, 2, "Display Order *",  tfFieldOrder);
        CrmAdminTool.addFormRow(form, gc, 3, "Source Column *",  tfSourceCol);
        CrmAdminTool.addFormRow(form, gc, 4, "JSON Path *",      tfJsonField);
        CrmAdminTool.addFormRow(form, gc, 5, "Data Type",        cbDataType);
        CrmAdminTool.addFormRow(form, gc, 6, "Date Format",      tfDateFormat);
        CrmAdminTool.addFormRow(form, gc, 7, "Is Mandatory",     cbIsMandatory);
        CrmAdminTool.addFormRow(form, gc, 8, "Is Active",        cbIsActive);

        gc.gridx = 0; gc.gridy = 9; gc.gridwidth = 2;
        JLabel hint = new JLabel(
            "Date Format e.g. DD-MON-YY HH24:MI");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        form.add(hint, gc);

        gc.gridy = 10; gc.gridwidth = 2;
        form.add(buildButtons(), gc);

        outer.add(form, BorderLayout.NORTH);
        return outer;
    }

    private JPanel buildButtons() {
        JPanel p = new JPanel(new GridLayout(2, 3, 8, 8));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new EmptyBorder(10, 0, 0, 0));

        JButton btnSave    = CrmAdminTool.mkBtn("Save Mapping",  CrmAdminTool.BTN_BLUE);
        JButton btnEnable  = CrmAdminTool.mkBtn("Enable",        CrmAdminTool.BTN_GREEN);
        JButton btnDisable = CrmAdminTool.mkBtn("Disable",       CrmAdminTool.BTN_RED);
        JButton btnLoad    = CrmAdminTool.mkBtn("Load Selected", CrmAdminTool.BTN_GREY);
        JButton btnClear   = CrmAdminTool.mkBtn("Clear Form",    CrmAdminTool.BTN_GREY);
        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh",       CrmAdminTool.BTN_GREY);

        btnSave   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { save(); }
        });
        btnEnable .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { setActive("Y"); }
        });
        btnDisable.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { setActive("N"); }
        });
        btnLoad   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadSelected(); }
        });
        btnClear  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { clearForm(); }
        });
        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadMappings(); }
        });

        p.add(btnSave);   p.add(btnEnable);  p.add(btnDisable);
        p.add(btnLoad);   p.add(btnClear);   p.add(btnRefresh);
        return p;
    }

    private JPanel buildTable() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(12, 6, 12, 12));

        JLabel lbl = new JLabel("Field Mappings");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Map ID", "JSON Mapping Name", "Display Order",
            "Source Column", "JSON Path", "Data Type",
            "Date Format", "Is Mandatory", "Active"
        };
        model = CrmAdminTool.mkModel(cols);
        table = CrmAdminTool.mkTable(model);
        table.getColumnModel().getColumn(8)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());

        int[] w = {60, 160, 50, 140, 140, 80, 150, 100, 55};
        for (int i = 0; i < w.length; i++)
            table.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        table.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2) loadSelected();
            }
        });

        p.add(CrmAdminTool.mkScroll(table), BorderLayout.CENTER);

        JLabel hint = new JLabel("  Double-click to edit");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        p.add(hint, BorderLayout.SOUTH);
        return p;
    }

    void refresh() {
        loadServiceList();
    }

    private void loadServiceList() {
        String q = app.sql("query.service.names.mapping");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            Object sel = cbService.getSelectedItem();
            cbService.removeAllItems();
            cbService.addItem("-- Select Service --");
            int count = 0;
            while (rs.next()) {
                cbService.addItem(rs.getString(1));
                count++;
            }
            CrmAdminTool.LOGGER.log("INFO",
                "MAPPING SERVICE DROPDOWN loaded: " +
                count + " JSON_MAPPING_NAME values");
            if (sel != null) cbService.setSelectedItem(sel);
        } catch (SQLException ex) {
            CrmAdminTool.LOGGER.error(
                "MAPPING SERVICE LIST FAILED", ex);
            app.setStatus("Service list error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadMappings() {
        String svc = (String) cbService.getSelectedItem();
        if (svc == null || svc.startsWith("--")) {
            model.setRowCount(0);
            app.setStatus("Select a service to load mappings.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        String q = app.sql("query.mapping.list");
        if (q == null) return;

        // Debug log -- show exact query and parameter
        CrmAdminTool.LOGGER.log("INFO",
            "MAPPING QUERY CALLED for service: [" + svc + "]");
        CrmAdminTool.LOGGER.log("INFO",
            "MAPPING SQL: " + q.substring(0, Math.min(200, q.length())));

        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, svc);
            ResultSet rs = ps.executeQuery();
            ResultSetMetaData meta = rs.getMetaData();

            // Log column names returned
            StringBuilder colNames = new StringBuilder("MAPPING COLUMNS: ");
            for (int i = 1; i <= meta.getColumnCount(); i++) {
                colNames.append(meta.getColumnName(i));
                if (i < meta.getColumnCount()) colNames.append(", ");
            }
            CrmAdminTool.LOGGER.log("INFO", colNames.toString());

            model.setRowCount(0);
            int rowCount = 0;
            while (rs.next()) {
                model.addRow(new Object[]{
                    rs.getString(1), rs.getString(2), rs.getString(3),
                    rs.getString(4), rs.getString(5), rs.getString(6),
                    rs.getString(7), rs.getString(8), rs.getString(9)
                });
                rowCount++;
            }
            CrmAdminTool.LOGGER.log("INFO",
                "MAPPING ROWS RETURNED: " + rowCount +
                " for service: " + svc);
            app.setStatus("Mappings loaded: " + rowCount +
                " for " + svc, CrmAdminTool.CLR_SUCCESS);

        } catch (SQLException ex) {
            CrmAdminTool.LOGGER.error(
                "MAPPING LOAD FAILED for [" + svc + "]", ex);
            app.setStatus("Mapping load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void save() {
        String svc      = (String) cbService.getSelectedItem();
        String srcCol   = tfSourceCol.getText().trim().toUpperCase();
        String jsonField= tfJsonField.getText().trim();
        String order    = tfFieldOrder.getText().trim();

        if (svc == null || svc.startsWith("--")
                || srcCol.isEmpty() || jsonField.isEmpty()
                || order.isEmpty()) {
            app.setStatus(
                "Service, Field Order, Source Column and JSON Field required.",
                CrmAdminTool.CLR_ERROR);
            return;
        }

        String q = app.sql("query.mapping.save");
        if (q == null) return;

        // Show SQL preview before executing
        Object[] previewParams = {
            svc, srcCol, order, jsonField,
            cbDataType.getSelectedItem(),
            tfDateFormat.getText().trim(),
            cbIsMandatory.getSelectedItem(),
            cbIsActive.getSelectedItem()
        };
        if (!CrmAdminTool.showSqlPreview(
                this, "Save Mapping: " + svc + " - " + srcCol,
                q, previewParams))
            return;

        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, svc);
            ps.setString(2, srcCol);
            ps.setString(3, order);
            ps.setString(4, jsonField);
            ps.setString(5, (String) cbDataType.getSelectedItem());
            ps.setString(6, tfDateFormat.getText().trim().isEmpty()
                ? null : tfDateFormat.getText().trim());
            ps.setString(7, (String) cbIsMandatory.getSelectedItem());
            ps.setString(8, (String) cbIsActive.getSelectedItem());
            ps.setString(9,  svc);
            ps.setString(10, order);
            ps.setString(11, srcCol);
            ps.setString(12, jsonField);
            ps.setString(13, (String) cbDataType.getSelectedItem());
            ps.setString(14, tfDateFormat.getText().trim().isEmpty()
                ? null : tfDateFormat.getText().trim());
            ps.setString(15, (String) cbIsMandatory.getSelectedItem());
            ps.setString(16, (String) cbIsActive.getSelectedItem());
            ps.executeUpdate();
            con.commit();
            app.setStatus("Mapping saved for " + svc + " - " + srcCol,
                CrmAdminTool.CLR_SUCCESS);
            clearForm();
            loadMappings();
        } catch (SQLException ex) {
            app.setStatus("Save error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void setActive(String flag) {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a mapping first.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        String mapId = (String) model.getValueAt(row, 0);
        String q = app.sql("query.mapping.set.active");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, flag);
            ps.setString(2, mapId);
            ps.executeUpdate();
            con.commit();
            app.setStatus("Mapping " + mapId + " set to " +
                ("Y".equals(flag) ? "ACTIVE" : "INACTIVE"),
                CrmAdminTool.CLR_SUCCESS);
            loadMappings();
        } catch (SQLException ex) {
            app.setStatus("Update error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadSelected() {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a row first.", CrmAdminTool.CLR_WARN);
            return;
        }
        cbService     .setSelectedItem(str(model.getValueAt(row, 1)));
        tfFieldOrder  .setText(str(model.getValueAt(row, 2)));
        tfSourceCol   .setText(str(model.getValueAt(row, 3)));
        tfJsonField   .setText(str(model.getValueAt(row, 4)));
        cbDataType    .setSelectedItem(str(model.getValueAt(row, 5)));
        tfDateFormat  .setText(str(model.getValueAt(row, 6)));
        cbIsMandatory .setSelectedItem(str(model.getValueAt(row, 7)));
        cbIsActive    .setSelectedItem(str(model.getValueAt(row, 8)));
        app.setStatus("Loaded mapping for " +
            str(model.getValueAt(row, 3)),
            CrmAdminTool.CLR_LABEL);
    }

    private void clearForm() {
        tfFieldOrder.setText(""); tfSourceCol.setText("");
        tfJsonField.setText(""); tfDateFormat.setText("");
        cbDataType.setSelectedIndex(0);
        cbIsMandatory.setSelectedIndex(0);
        cbIsActive.setSelectedIndex(0);
    }

    private String str(Object o) {
        return o == null ? "" : o.toString();
    }
}

// =============================================================================
//  TAB 4: WATERMARK
// =============================================================================
class WatermarkTab extends JPanel {

    private CrmAdminTool app;
    private JTable       table;
    private DefaultTableModel model;

    WatermarkTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(12, 12, 12, 12));

        JLabel lbl = new JLabel(
            "Watermark -- Last Processed Timestamp per Service");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Service Name", "Last Processed TS",
            "Last Run Status", "Last Run Records", "Registry ID"
        };
        model = CrmAdminTool.mkModel(cols);
        table = CrmAdminTool.mkTable(model);

        int[] w = {200, 160, 160, 130, 100};
        for (int i = 0; i < w.length; i++)
            table.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        p.add(CrmAdminTool.mkScroll(table), BorderLayout.CENTER);
        p.add(buildButtons(), BorderLayout.SOUTH);
        add(p, BorderLayout.CENTER);
    }

    private JPanel buildButtons() {
        JPanel p = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 8));
        p.setBackground(CrmAdminTool.CLR_BG);
        p.setBorder(new MatteBorder(1, 0, 0, 0, CrmAdminTool.CLR_BORDER));

        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh",
            CrmAdminTool.BTN_BLUE);
        JButton btnReset   = CrmAdminTool.mkBtn("Reset Watermark (Full Re-push)",
            CrmAdminTool.BTN_RED);
        JButton btnSetDate = CrmAdminTool.mkBtn("Set Watermark Date",
            CrmAdminTool.BTN_ORANGE);

        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { refresh(); }
        });
        btnReset  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { resetWatermark(); }
        });
        btnSetDate.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { setWatermarkDate(); }
        });

        p.add(btnRefresh);
        p.add(btnReset);
        p.add(btnSetDate);

        JLabel hint = new JLabel(
            "  Reset = sets watermark to NULL -- forces full re-push of all records");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_WARN);
        p.add(hint);
        return p;
    }

    void refresh() {
        String q = app.sql("query.watermark.list");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            model.setRowCount(0);
            while (rs.next()) {
                model.addRow(new Object[]{
                    rs.getString(1), rs.getString(2),
                    rs.getString(3), rs.getString(4),
                    rs.getString(5)
                });
            }
            app.setStatus("Watermarks loaded: " + model.getRowCount(),
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void resetWatermark() {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a service first.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        String svc = (String) model.getValueAt(row, 0);
        int ok = JOptionPane.showConfirmDialog(this,
            "Reset watermark for: " + svc + "?\n\n" +
            "This will force a FULL re-push of ALL records\n" +
            "at the next scheduled run.\n\n" +
            "Are you sure?",
            "Confirm Reset",
            JOptionPane.YES_NO_OPTION,
            JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;

        String q = app.sql("query.watermark.reset");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, svc);
            ps.executeUpdate();
            con.commit();
            app.setStatus("Watermark reset for " + svc +
                " -- full re-push at next run.",
                CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Reset error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void setWatermarkDate() {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a service first.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        String svc = (String) model.getValueAt(row, 0);
        String date = JOptionPane.showInputDialog(this,
            "Enter watermark date for: " + svc + "\n" +
            "Format: DD-MON-YY HH24:MI (e.g. 01-JAN-26 00:00)",
            "Set Watermark Date",
            JOptionPane.QUESTION_MESSAGE);
        if (date == null || date.trim().isEmpty()) return;

        String q = app.sql("query.watermark.set.date");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, date.trim());
            ps.setString(2, svc);
            ps.executeUpdate();
            con.commit();
            app.setStatus("Watermark set to " + date +
                " for " + svc, CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Set date error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }
}

// =============================================================================
//  TAB 5: ERROR CODES
// =============================================================================
class ErrorCodeTab extends JPanel {

    private CrmAdminTool app;
    private JTextField   tfCode, tfDescription;
    private JComboBox    cbCategory, cbIsRetryable;
    private JTable       table;
    private DefaultTableModel model;

    ErrorCodeTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        JSplitPane sp = new JSplitPane(
            JSplitPane.HORIZONTAL_SPLIT,
            buildForm(), buildTable());
        sp.setDividerLocation(360);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        add(sp, BorderLayout.CENTER);
    }

    private JPanel buildForm() {
        JPanel outer = CrmAdminTool.mkPanel(new BorderLayout());
        outer.setBorder(new EmptyBorder(12, 12, 12, 6));

        JPanel form = CrmAdminTool.mkFormPanel();
        GridBagConstraints gc = CrmAdminTool.mkGc();

        CrmAdminTool.addSectionLabel(form, gc, 0, "Error Code Details");

        tfCode        = CrmAdminTool.mkField(200);
        cbCategory    = CrmAdminTool.mkCombo(new String[]{
            "RETRYABLE","NON_RETRYABLE","SUCCESS","TIMEOUT","INFO"});
        tfDescription = CrmAdminTool.mkField(200);
        cbIsRetryable = CrmAdminTool.mkCombo(new String[]{"Y","N"});

        CrmAdminTool.addFormRow(form, gc, 1, "Error Code *",   tfCode);
        CrmAdminTool.addFormRow(form, gc, 2, "Category",       cbCategory);
        CrmAdminTool.addFormRow(form, gc, 3, "Description",    tfDescription);
        CrmAdminTool.addFormRow(form, gc, 4, "Is Retryable",   cbIsRetryable);

        gc.gridx = 0; gc.gridy = 5; gc.gridwidth = 2;
        form.add(buildButtons(), gc);

        outer.add(form, BorderLayout.NORTH);
        return outer;
    }

    private JPanel buildButtons() {
        JPanel p = new JPanel(new GridLayout(2, 2, 8, 8));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new EmptyBorder(10, 0, 0, 0));

        JButton btnSave    = CrmAdminTool.mkBtn("Save",          CrmAdminTool.BTN_BLUE);
        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh",       CrmAdminTool.BTN_GREY);
        JButton btnLoad    = CrmAdminTool.mkBtn("Load Selected", CrmAdminTool.BTN_GREY);
        JButton btnClear   = CrmAdminTool.mkBtn("Clear Form",    CrmAdminTool.BTN_GREY);

        btnSave   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { save(); }
        });
        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { refresh(); }
        });
        btnLoad   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadSelected(); }
        });
        btnClear  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { clearForm(); }
        });

        p.add(btnSave); p.add(btnRefresh);
        p.add(btnLoad); p.add(btnClear);
        return p;
    }

    private JPanel buildTable() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(12, 6, 12, 12));

        JLabel lbl = new JLabel("Error Code Master");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Error Code", "Category", "Description", "Is Retryable"
        };
        model = CrmAdminTool.mkModel(cols);
        table = CrmAdminTool.mkTable(model);
        table.getColumnModel().getColumn(3)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());

        int[] w = {160, 130, 380, 100};
        for (int i = 0; i < w.length; i++)
            table.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        table.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2) loadSelected();
            }
        });

        p.add(CrmAdminTool.mkScroll(table), BorderLayout.CENTER);
        return p;
    }

    void refresh() {
        String q = app.sql("query.errorcode.list");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            model.setRowCount(0);
            while (rs.next()) {
                model.addRow(new Object[]{
                    rs.getString(1), rs.getString(2),
                    rs.getString(3), rs.getString(4)
                });
            }
            app.updateTabTitle(4,
                "Error Codes (" + model.getRowCount() + ")");
            app.setStatus("Error codes loaded: " + model.getRowCount(),
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void save() {
        String code = tfCode.getText().trim().toUpperCase();
        if (code.isEmpty()) {
            app.setStatus("Error Code is required.",
                CrmAdminTool.CLR_ERROR);
            return;
        }
        String q = app.sql("query.errorcode.save");
        if (q == null) return;

        // Show SQL preview before executing
        Object[] previewParams = {
            code,
            cbCategory.getSelectedItem(),
            tfDescription.getText().trim(),
            cbIsRetryable.getSelectedItem()
        };
        if (!CrmAdminTool.showSqlPreview(
                this, "Save Error Code: " + code, q, previewParams))
            return;

        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, code);
            ps.setString(2, (String) cbCategory.getSelectedItem());
            ps.setString(3, tfDescription.getText().trim());
            ps.setString(4, (String) cbIsRetryable.getSelectedItem());
            ps.setString(5, code);
            ps.executeUpdate();
            con.commit();
            app.setStatus("Error code " + code + " saved.",
                CrmAdminTool.CLR_SUCCESS);
            clearForm();
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Save error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadSelected() {
        int row = table.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a row first.", CrmAdminTool.CLR_WARN);
            return;
        }
        tfCode       .setText(str(model.getValueAt(row, 0)));
        cbCategory   .setSelectedItem(str(model.getValueAt(row, 1)));
        tfDescription.setText(str(model.getValueAt(row, 2)));
        cbIsRetryable.setSelectedItem(str(model.getValueAt(row, 3)));
    }

    private void clearForm() {
        tfCode.setText("");
        tfDescription.setText("");
        cbCategory.setSelectedIndex(0);
        cbIsRetryable.setSelectedIndex(1);
    }

    private String str(Object o) {
        return o == null ? "" : o.toString();
    }
}

// =============================================================================
//  TAB 6: MONITOR
// =============================================================================
class MonitorTab extends JPanel {

    private CrmAdminTool      app;
    private JTabbedPane       monTabs;
    private JTable            tblDash, tblMain, tblAction, tblRetry, tblTriage, tblCallbackAudit;
    private DefaultTableModel mdlDash, mdlMain, mdlAction, mdlRetry, mdlTriage, mdlCallbackAudit;
    private JComboBox         cbService, cbStatus;
    private JTextField        tfFromDate, tfToDate, tfRecordId;
    private JLabel            lblLastRefresh;

    MonitorTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        add(buildTopBar(),  BorderLayout.NORTH);
        monTabs = new JTabbedPane();
        monTabs.setFont(CrmAdminTool.FONT_LABEL);
        monTabs.addTab("Dashboard",      buildDashTab());
        monTabs.addTab("All Records",    buildMainTab());
        monTabs.addTab("Action Needed",  buildActionTab());
        monTabs.addTab("Retry Queue",    buildRetryTab());
        monTabs.addTab("Error Triage",   buildTriageTab());
        monTabs.addTab("Callback Audit", buildCallbackAuditTab());
        add(monTabs, BorderLayout.CENTER);
    }

    private JPanel buildTopBar() {
        JPanel p = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 6));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new CompoundBorder(
            new MatteBorder(0, 0, 1, 0, CrmAdminTool.CLR_BORDER),
            new EmptyBorder(4, 8, 4, 8)));

        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh All",
            CrmAdminTool.BTN_BLUE);
        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { refresh(); }
        });

        lblLastRefresh = new JLabel("Last refresh: --");
        lblLastRefresh.setFont(CrmAdminTool.FONT_STATUS);
        lblLastRefresh.setForeground(CrmAdminTool.CLR_LABEL);

        p.add(btnRefresh);
        p.add(lblLastRefresh);
        return p;
    }

    private JPanel buildDashTab() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(10, 10, 10, 10));
        String[] cols = {
            "Service","Total","Success","Pending",
            "Val Failed","Duplicate","Auto Retry",
            "Exhausted","Parent Missing","Action Needed","Last Sent"
        };
        mdlDash = CrmAdminTool.mkModel(cols);
        tblDash = CrmAdminTool.mkTable(mdlDash);
        tblDash.getColumnModel().getColumn(9)
            .setCellRenderer(new ActionNeededRenderer());
        int[] w = {170,50,65,65,80,75,80,75,105,100,130};
        for (int i = 0; i < w.length; i++)
            tblDash.getColumnModel().getColumn(i).setPreferredWidth(w[i]);
        p.add(CrmAdminTool.mkScroll(tblDash), BorderLayout.CENTER);
        return p;
    }

    private JPanel buildMainTab() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(10, 10));
        p.setBorder(new EmptyBorder(10, 10, 10, 10));
        p.add(buildFilterBar(), BorderLayout.NORTH);

        String[] cols = {
            "Log ID","Service","Record ID","Status",
            "Data Sent","Failed Fields","CRM Response",
            "Error Detail","CRM Ref","Sent Date",
            "Callback Date","Retry","Manual Retry","Executed By","Action"
        };
        mdlMain = CrmAdminTool.mkModel(cols);
        tblMain = CrmAdminTool.mkTable(mdlMain);
        tblMain.getColumnModel().getColumn(3)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());
        tblMain.getColumnModel().getColumn(4).setPreferredWidth(300);
        tblMain.getColumnModel().getColumn(5).setPreferredWidth(200);
        // EXECUTED_BY column -- index 13 -- color by job type
        tblMain.getColumnModel().getColumn(13)
            .setCellRenderer(new javax.swing.table.DefaultTableCellRenderer() {
                public java.awt.Component getTableCellRendererComponent(
                        JTable table, Object value, boolean isSelected,
                        boolean hasFocus, int row, int column) {
                    super.getTableCellRendererComponent(
                        table, value, isSelected, hasFocus, row, column);
                    if (!isSelected) {
                        String v = value == null ? "" : value.toString();
                        if (v.startsWith("OUTBOUND JOB")) {
                            setForeground(new java.awt.Color(30, 100, 200));
                            setBackground(new java.awt.Color(230, 240, 255));
                        } else if (v.startsWith("RETRY JOB")) {
                            setForeground(new java.awt.Color(160, 100, 0));
                            setBackground(new java.awt.Color(255, 245, 220));
                        } else if (v.startsWith("TIMEOUT JOB")) {
                            setForeground(new java.awt.Color(150, 50, 150));
                            setBackground(new java.awt.Color(245, 230, 255));
                        } else if (v.startsWith("MANUAL RETRY")) {
                            setForeground(new java.awt.Color(180, 60, 0));
                            setBackground(new java.awt.Color(255, 235, 220));
                        } else {
                            setForeground(java.awt.Color.DARK_GRAY);
                            setBackground(java.awt.Color.WHITE);
                        }
                    }
                    return this;
                }
            });
        tblMain.getColumnModel().getColumn(13).setPreferredWidth(130);
        tblMain.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2) showDetail(tblMain, mdlMain);
            }
        });
        p.add(CrmAdminTool.mkScroll(tblMain), BorderLayout.CENTER);
        p.add(buildMainButtons(), BorderLayout.SOUTH);
        return p;
    }

    private JPanel buildFilterBar() {
        JPanel p = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 6));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new CompoundBorder(
            new LineBorder(CrmAdminTool.CLR_BORDER, 1),
            new EmptyBorder(4, 8, 4, 8)));

        cbService  = new JComboBox();
        cbService.setFont(CrmAdminTool.FONT_LABEL);
        cbService.setPreferredSize(new Dimension(200, 28));

        cbStatus = new JComboBox();
        cbStatus.setFont(CrmAdminTool.FONT_LABEL);
        cbStatus.setPreferredSize(new Dimension(160, 28));

        tfFromDate = CrmAdminTool.mkField(110);
        tfToDate   = CrmAdminTool.mkField(110);
        tfRecordId = CrmAdminTool.mkField(120);

        SimpleDateFormat sdf = new SimpleDateFormat("dd-MMM-yy");
        tfFromDate.setText(sdf.format(
            new Date(System.currentTimeMillis() - 7L * 86400000L)));
        tfToDate.setText(sdf.format(new Date()));

        p.add(CrmAdminTool.mkLabel("Service:"));   p.add(cbService);
        p.add(CrmAdminTool.mkLabel("Status:"));    p.add(cbStatus);
        p.add(CrmAdminTool.mkLabel("From:"));      p.add(tfFromDate);
        p.add(CrmAdminTool.mkLabel("To:"));        p.add(tfToDate);
        p.add(CrmAdminTool.mkLabel("Record ID:")); p.add(tfRecordId);
        return p;
    }

    private JPanel buildMainButtons() {
        JPanel p = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 6));
        p.setBackground(CrmAdminTool.CLR_BG);
        p.setBorder(new MatteBorder(1, 0, 0, 0, CrmAdminTool.CLR_BORDER));

        JButton btnSearch  = CrmAdminTool.mkBtn("Search",          CrmAdminTool.BTN_BLUE);
        JButton btnClear   = CrmAdminTool.mkBtn("Clear Filters",   CrmAdminTool.BTN_GREY);
        JButton btnRetry   = CrmAdminTool.mkBtn("Manual Retry",    CrmAdminTool.BTN_ORANGE);
        JButton btnDetail  = CrmAdminTool.mkBtn("View Full Detail", CrmAdminTool.BTN_GREEN);

        btnSearch .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadMain(); }
        });
        btnClear  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { clearFilters(); }
        });
        btnRetry  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                manualRetry(tblMain, mdlMain);
            }
        });
        btnDetail .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                showDetail(tblMain, mdlMain);
            }
        });

        p.add(btnSearch); p.add(btnClear);
        p.add(btnRetry);  p.add(btnDetail);
        return p;
    }

    private JPanel buildActionTab() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(10, 10, 10, 10));

        JLabel hint = new JLabel(
            "Records requiring manual attention: " +
            "VALIDATION_FAILED, EXHAUSTED, RECORD_NOT_FOUND, CRM_REJECTED");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_WARN);
        hint.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(hint, BorderLayout.NORTH);

        String[] cols = {
            "Log ID","Service","Record ID","Status",
            "Data Sent","Failed Fields","CRM Response",
            "Error Detail","Sent Date","Callback Date",
            "Retry","Action Needed"
        };
        mdlAction = CrmAdminTool.mkModel(cols);
        tblAction = CrmAdminTool.mkTable(mdlAction);
        tblAction.getColumnModel().getColumn(3)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());
        tblAction.getColumnModel().getColumn(4).setPreferredWidth(280);
        tblAction.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2)
                    showDetail(tblAction, mdlAction);
            }
        });
        p.add(CrmAdminTool.mkScroll(tblAction), BorderLayout.CENTER);

        JPanel bot = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 6));
        bot.setBackground(CrmAdminTool.CLR_BG);
        bot.setBorder(new MatteBorder(1, 0, 0, 0, CrmAdminTool.CLR_BORDER));
        JButton btnRetry  = CrmAdminTool.mkBtn("Manual Retry",
            CrmAdminTool.BTN_ORANGE);
        JButton btnDetail = CrmAdminTool.mkBtn("View Full Detail",
            CrmAdminTool.BTN_GREEN);
        btnRetry .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                manualRetry(tblAction, mdlAction);
            }
        });
        btnDetail.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                showDetail(tblAction, mdlAction);
            }
        });
        bot.add(btnRetry); bot.add(btnDetail);
        p.add(bot, BorderLayout.SOUTH);
        return p;
    }

    private JPanel buildRetryTab() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(10, 10, 10, 10));

        JLabel hint = new JLabel(
            "Records queued for manual retry -- waiting for RUN_RETRY_JOB");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_SUCCESS);
        hint.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(hint, BorderLayout.NORTH);

        String[] cols = {
            "Log ID","Service","Record ID","Status",
            "Data Sent","Error Detail",
            "Sent Date","Retry Queued At","Retry Progress"
        };
        mdlRetry = CrmAdminTool.mkModel(cols);
        tblRetry = CrmAdminTool.mkTable(mdlRetry);
        tblRetry.getColumnModel().getColumn(4).setPreferredWidth(300);

        p.add(CrmAdminTool.mkScroll(tblRetry), BorderLayout.CENTER);

        JPanel bot = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 6));
        bot.setBackground(CrmAdminTool.CLR_BG);
        bot.setBorder(new MatteBorder(1, 0, 0, 0, CrmAdminTool.CLR_BORDER));
        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh",
            CrmAdminTool.BTN_BLUE);
        JButton btnDetail  = CrmAdminTool.mkBtn("View Full Detail",
            CrmAdminTool.BTN_GREEN);
        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadRetry(); }
        });
        btnDetail .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                showDetail(tblRetry, mdlRetry);
            }
        });
        bot.add(btnRefresh); bot.add(btnDetail);
        p.add(bot, BorderLayout.SOUTH);
        return p;
    }

    private JPanel buildTriageTab() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(10, 10, 10, 10));

        // Header hint
        JLabel hint = new JLabel(
            "Priority triage: identify root-cause errors to fix first.  " +
            "RED = must fix manually   YELLOW = retry manually   GREEN = auto-retry will handle");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        hint.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(hint, BorderLayout.NORTH);

        String[] cols = {
            "Priority","Status","Error Code","Error Description",
            "Retryable","Record Count","Services Affected",
            "First Occurrence","Last Occurrence","Action Required"
        };
        mdlTriage = CrmAdminTool.mkModel(cols);
        tblTriage = CrmAdminTool.mkTable(mdlTriage);

        // Column widths
        int[] w = {60,110,140,200,70,90,100,150,150,200};
        for (int i = 0; i < w.length; i++)
            tblTriage.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        // Color renderer for Priority column
        tblTriage.getColumnModel().getColumn(0)
            .setCellRenderer(new javax.swing.table.DefaultTableCellRenderer() {
                public java.awt.Component getTableCellRendererComponent(
                        JTable table, Object value, boolean isSelected,
                        boolean hasFocus, int row, int column) {
                    super.getTableCellRendererComponent(
                        table, value, isSelected, hasFocus, row, column);
                    setHorizontalAlignment(CENTER);
                    setOpaque(true);
                    String v = value == null ? "" : value.toString();
                    if ("1-CRITICAL".equals(v)) {
                        setBackground(new java.awt.Color(192, 0, 0));
                        setForeground(java.awt.Color.WHITE);
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else if ("2-MANUAL".equals(v)) {
                        setBackground(new java.awt.Color(197, 90, 17));
                        setForeground(java.awt.Color.WHITE);
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else if ("3-AUTO".equals(v)) {
                        setBackground(new java.awt.Color(56, 87, 35));
                        setForeground(java.awt.Color.WHITE);
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else {
                        setBackground(java.awt.Color.WHITE);
                        setForeground(java.awt.Color.DARK_GRAY);
                        setFont(getFont().deriveFont(java.awt.Font.PLAIN));
                    }
                    return this;
                }
            });

        // Action Required column renderer
        tblTriage.getColumnModel().getColumn(9)
            .setCellRenderer(new javax.swing.table.DefaultTableCellRenderer() {
                public java.awt.Component getTableCellRendererComponent(
                        JTable table, Object value, boolean isSelected,
                        boolean hasFocus, int row, int column) {
                    super.getTableCellRendererComponent(
                        table, value, isSelected, hasFocus, row, column);
                    setOpaque(true);
                    String v = value == null ? "" : value.toString();
                    if (v.startsWith("FIX DATA")) {
                        setBackground(new java.awt.Color(255, 230, 230));
                        setForeground(new java.awt.Color(192, 0, 0));
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else if (v.startsWith("MANUAL RETRY")) {
                        setBackground(new java.awt.Color(255, 242, 204));
                        setForeground(new java.awt.Color(140, 80, 0));
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else if (v.startsWith("AUTO")) {
                        setBackground(new java.awt.Color(226, 239, 218));
                        setForeground(new java.awt.Color(56, 87, 35));
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else {
                        setBackground(java.awt.Color.WHITE);
                        setForeground(java.awt.Color.DARK_GRAY);
                        setFont(getFont().deriveFont(java.awt.Font.PLAIN));
                    }
                    return this;
                }
            });

        p.add(CrmAdminTool.mkScroll(tblTriage), BorderLayout.CENTER);

        // Bottom buttons
        JPanel bot = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 6));
        bot.setBackground(CrmAdminTool.CLR_BG);
        bot.setBorder(new MatteBorder(1, 0, 0, 0, CrmAdminTool.CLR_BORDER));

        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh", CrmAdminTool.BTN_BLUE);
        JButton btnExport  = CrmAdminTool.mkBtn("Export to Log", CrmAdminTool.BTN_GREEN);

        JLabel legend = new JLabel(
            "  Priority:  1-CRITICAL = fix data/config now   " +
            "2-MANUAL = manual retry after fix   " +
            "3-AUTO = retry job will handle");
        legend.setFont(CrmAdminTool.FONT_STATUS);
        legend.setForeground(CrmAdminTool.CLR_LABEL);

        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { loadTriage(); }
        });
        btnExport.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                exportTriageToLog();
            }
        });

        bot.add(btnRefresh);
        bot.add(btnExport);
        bot.add(legend);
        p.add(bot, BorderLayout.SOUTH);
        return p;
    }

    private void loadTriage() {
        String q = app.sql("query.error.triage");
        if (q == null) {
            app.setStatus("query.error.triage not found in properties.",
                CrmAdminTool.CLR_ERROR);
            return;
        }
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            mdlTriage.setRowCount(0);
            mdlTriage.setColumnCount(0);
            String[] cols = {
                "Priority","Status","Error Code","Error Description",
                "Retryable","Record Count","Services Affected",
                "First Occurrence","Last Occurrence","Action Required"
            };
            for (String c : cols) mdlTriage.addColumn(c);
            while (rs.next()) {
                String status     = rs.getString("FINAL_STATUS");
                String errCode    = rs.getString("ERROR_CODE");
                String errDesc    = rs.getString("ERROR_DESCRIPTION");
                String retryable  = rs.getString("IS_RETRYABLE");
                String count      = rs.getString("RECORD_COUNT");
                String svcs       = rs.getString("SERVICES_AFFECTED");
                String firstOcc   = rs.getString("FIRST_OCCURRENCE");
                String lastOcc    = rs.getString("LAST_OCCURRENCE");
                // Determine priority and action
                String priority;
                String action;
                boolean isExhausted = "EXHAUSTED".equals(status)
                    || "VALIDATION_FAILED".equals(status)
                    || "CRM_REJECTED".equals(status);
                boolean isRetryable = "Y".equals(retryable);
                if (isExhausted && !isRetryable) {
                    priority = "1-CRITICAL";
                    action   = "FIX DATA/CONFIG -- retry job will not pick up";
                } else if (isExhausted && isRetryable) {
                    priority = "2-MANUAL";
                    action   = "MANUAL RETRY -- fix issue then click Manual Retry";
                } else if (!isExhausted && isRetryable) {
                    priority = "3-AUTO";
                    action   = "AUTO -- retry job will handle within 30 min";
                } else {
                    priority = "2-MANUAL";
                    action   = "MANUAL RETRY -- review error detail";
                }
                mdlTriage.addRow(new Object[]{
                    priority, status, errCode, errDesc,
                    retryable, count, svcs,
                    firstOcc, lastOcc, action
                });
            }
            // Sort: priority 1 first (already from ORDER BY in SQL)
            int cnt = mdlTriage.getRowCount();
            monTabs.setTitleAt(4,
                "Error Triage" + (cnt > 0 ? " (" + cnt + ")" : ""));
            app.setStatus("Error triage loaded -- " + cnt + " error group(s).",
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Triage load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
            CrmAdminTool.LOGGER.log("ERROR", "loadTriage: " + ex.getMessage());
        }
    }

    private void exportTriageToLog() {
        if (mdlTriage.getRowCount() == 0) {
            app.setStatus("No triage data to export.", CrmAdminTool.CLR_WARN);
            return;
        }
        StringBuilder sb = new StringBuilder();
        sb.append("=== ERROR TRIAGE REPORT ===\n");
        sb.append(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date()));
        sb.append("\n");
        sb.append(repeatChar('-', 80)).append("\n");
        for (int r = 0; r < mdlTriage.getRowCount(); r++) {
            sb.append(String.format(
                "[%s] Status=%-20s Code=%-25s Count=%-5s Retryable=%s\n",
                mdlTriage.getValueAt(r, 0),
                mdlTriage.getValueAt(r, 1),
                mdlTriage.getValueAt(r, 2),
                mdlTriage.getValueAt(r, 5),
                mdlTriage.getValueAt(r, 4)));
            sb.append(String.format(
                "         Action: %s\n",
                mdlTriage.getValueAt(r, 9)));
            sb.append(String.format(
                "         First: %s   Last: %s   Services: %s\n",
                mdlTriage.getValueAt(r, 7),
                mdlTriage.getValueAt(r, 8),
                mdlTriage.getValueAt(r, 6)));
            sb.append("\n");
        }
        CrmAdminTool.LOGGER.log("INFO", sb.toString());
        app.setStatus("Triage report exported to log.", CrmAdminTool.CLR_SUCCESS);
        JOptionPane.showMessageDialog(this,
            "Triage report exported to CRM Admin Log.\nOpen View Log to see it.",
            "Exported", JOptionPane.INFORMATION_MESSAGE);
    }

    private String repeatChar(char c, int n) {
        StringBuilder sb = new StringBuilder(n);
        for (int i = 0; i < n; i++) sb.append(c);
        return sb.toString();
    }

    private JPanel buildCallbackAuditTab() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 8));
        p.setBorder(new EmptyBorder(10, 10, 10, 10));

        // Filter bar
        JPanel filterBar = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 6));
        filterBar.setBackground(CrmAdminTool.CLR_PANEL);
        filterBar.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createMatteBorder(0,0,1,0,CrmAdminTool.CLR_BORDER),
            BorderFactory.createEmptyBorder(4,4,4,4)));

        JLabel lblSvc   = new JLabel("Service:");
        JLabel lblCode  = new JLabel("Status Code:");
        JLabel lblFrom  = new JLabel("From Date:");
        JLabel lblTo    = new JLabel("To Date:");
        lblSvc  .setFont(CrmAdminTool.FONT_LABEL);
        lblCode .setFont(CrmAdminTool.FONT_LABEL);
        lblFrom .setFont(CrmAdminTool.FONT_LABEL);
        lblTo   .setFont(CrmAdminTool.FONT_LABEL);
        lblSvc  .setForeground(CrmAdminTool.CLR_LABEL);
        lblCode .setForeground(CrmAdminTool.CLR_LABEL);
        lblFrom .setForeground(CrmAdminTool.CLR_LABEL);
        lblTo   .setForeground(CrmAdminTool.CLR_LABEL);

        final JComboBox  cbAuditSvc  = new JComboBox(new String[]{"-- All Services --"});
        final JComboBox  cbAuditCode = new JComboBox(new String[]{
            "-- All --","CB_0000","CB_1002"});
        final JTextField tfAuditFrom = CrmAdminTool.mkField(100);
        final JTextField tfAuditTo   = CrmAdminTool.mkField(100);
        cbAuditSvc .setFont(CrmAdminTool.FONT_LABEL);
        cbAuditCode.setFont(CrmAdminTool.FONT_LABEL);
        cbAuditSvc .setBackground(Color.WHITE);
        cbAuditCode.setBackground(Color.WHITE);
        cbAuditSvc .setPreferredSize(new Dimension(180,26));

        // Populate service dropdown
        String qSvc = app.sql("query.service.names");
        if (qSvc != null) {
            try (Connection con = app.getConnection();
                 PreparedStatement ps = con.prepareStatement(qSvc);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) cbAuditSvc.addItem(rs.getString(1));
            } catch (Exception ex) { /* silent */ }
        }

        JButton btnSearch  = CrmAdminTool.mkBtn("Search",      CrmAdminTool.BTN_BLUE);
        JButton btnClear   = CrmAdminTool.mkBtn("Clear",       CrmAdminTool.BTN_GREY);
        JButton btnRefresh = CrmAdminTool.mkBtn("Refresh",     CrmAdminTool.BTN_GREY);

        filterBar.add(lblSvc);   filterBar.add(cbAuditSvc);
        filterBar.add(lblCode);  filterBar.add(cbAuditCode);
        filterBar.add(lblFrom);  filterBar.add(tfAuditFrom);
        filterBar.add(lblTo);    filterBar.add(tfAuditTo);
        filterBar.add(btnSearch);filterBar.add(btnClear);
        filterBar.add(btnRefresh);

        // Legend
        JPanel legendBar = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 4));
        legendBar.setBackground(CrmAdminTool.CLR_BG);
        JLabel l1 = new JLabel("  CB_0000 = Callback processed successfully");
        JLabel l2 = new JLabel("  CB_1002 = No matching log entry found (orphan callback)");
        l1.setFont(CrmAdminTool.FONT_ITALIC); l1.setForeground(new Color(55,87,35));
        l2.setFont(CrmAdminTool.FONT_ITALIC); l2.setForeground(new Color(192,0,0));
        legendBar.add(l1); legendBar.add(l2);

        // Table
        String[] cols = {
            "AUDIT_ID","RECEIVED_AT","SERVICE_NAME","X_UNIQUE_ID",
            "CHANNEL_ID","REQUEST_ID","STATUS_CODE_SENT","DESCRIPTION_SENT","RAW_PAYLOAD"
        };
        mdlCallbackAudit = CrmAdminTool.mkModel(cols);
        tblCallbackAudit = CrmAdminTool.mkTable(mdlCallbackAudit);

        // Double-click to show full detail
        tblCallbackAudit.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2)
                    showDetail(tblCallbackAudit, mdlCallbackAudit);
            }
        });

        int[] colWidths = {70,150,160,130,70,250,90,300,200};
        for (int i = 0; i < colWidths.length; i++)
            tblCallbackAudit.getColumnModel().getColumn(i)
                .setPreferredWidth(colWidths[i]);

        // Color renderer for Status Code column (index 6)
        tblCallbackAudit.getColumnModel().getColumn(6)
            .setCellRenderer(new javax.swing.table.DefaultTableCellRenderer() {
                public java.awt.Component getTableCellRendererComponent(
                        JTable table, Object value, boolean isSelected,
                        boolean hasFocus, int row, int column) {
                    super.getTableCellRendererComponent(
                        table, value, isSelected, hasFocus, row, column);
                    setOpaque(true);
                    setHorizontalAlignment(CENTER);
                    String v = value == null ? "" : value.toString();
                    if ("CB_0000".equals(v)) {
                        setBackground(new java.awt.Color(226,239,218));
                        setForeground(new java.awt.Color(55,87,35));
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else if ("CB_1002".equals(v)) {
                        setBackground(new java.awt.Color(252,228,228));
                        setForeground(new java.awt.Color(192,0,0));
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    } else {
                        setBackground(new java.awt.Color(255,242,204));
                        setForeground(new java.awt.Color(127,96,0));
                        setFont(getFont().deriveFont(java.awt.Font.BOLD));
                    }
                    return this;
                }
            });

        // North: filter + legend stacked
        JPanel north = new JPanel(new BorderLayout());
        north.setBackground(CrmAdminTool.CLR_BG);
        north.add(filterBar, BorderLayout.NORTH);
        north.add(legendBar, BorderLayout.SOUTH);
        p.add(north, BorderLayout.NORTH);
        p.add(CrmAdminTool.mkScroll(tblCallbackAudit), BorderLayout.CENTER);

        // Bottom info bar
        JPanel bot = new JPanel(new FlowLayout(FlowLayout.LEFT,10,6));
        bot.setBackground(CrmAdminTool.CLR_BG);
        bot.setBorder(new MatteBorder(1,0,0,0,CrmAdminTool.CLR_BORDER));
        final JLabel lblCount = new JLabel("0 record(s)");
        lblCount.setFont(CrmAdminTool.FONT_ITALIC);
        lblCount.setForeground(CrmAdminTool.CLR_LABEL);
        bot.add(lblCount);
        p.add(bot, BorderLayout.SOUTH);

        // Button actions
        btnSearch.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                String svc  = cbAuditSvc.getSelectedIndex()==0 ? null
                    : (String)cbAuditSvc.getSelectedItem();
                String code = cbAuditCode.getSelectedIndex()==0 ? null
                    : (String)cbAuditCode.getSelectedItem();
                String from = tfAuditFrom.getText().trim().isEmpty() ? null
                    : tfAuditFrom.getText().trim();
                String to   = tfAuditTo.getText().trim().isEmpty()   ? null
                    : tfAuditTo.getText().trim();
                loadCallbackAudit(svc, code, from, to, lblCount);
            }
        });
        btnRefresh.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                loadCallbackAudit(null, null, null, null, lblCount);
            }
        });
        btnClear.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                cbAuditSvc.setSelectedIndex(0);
                cbAuditCode.setSelectedIndex(0);
                tfAuditFrom.setText("");
                tfAuditTo.setText("");
                loadCallbackAudit(null, null, null, null, lblCount);
            }
        });

        return p;
    }

    private void loadCallbackAudit(
            String svc, String statusCode,
            String fromDate, String toDate, JLabel lblCount) {
        String q = app.sql("query.callback.audit");
        if (q == null) {
            app.setStatus("query.callback.audit not found in properties.",
                CrmAdminTool.CLR_ERROR);
            return;
        }
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, svc);       ps.setString(2, svc);
            ps.setString(3, statusCode);ps.setString(4, statusCode);
            ps.setString(5, fromDate);  ps.setString(6, fromDate);
            ps.setString(7, toDate);    ps.setString(8, toDate);
            try (ResultSet rs = ps.executeQuery()) {
                mdlCallbackAudit.setRowCount(0);
                mdlCallbackAudit.setColumnCount(0);
                String[] cols = {
                    "AUDIT_ID","RECEIVED_AT","SERVICE_NAME","X_UNIQUE_ID",
                    "CHANNEL_ID","REQUEST_ID","STATUS_CODE_SENT","DESCRIPTION_SENT","RAW_PAYLOAD"
                };
                for (String c : cols) mdlCallbackAudit.addColumn(c);
                int cnt = 0;
                while (rs.next()) {
                    mdlCallbackAudit.addRow(new Object[]{
                        rs.getString("AUDIT_ID"),
                        rs.getString("RECEIVED_AT"),
                        rs.getString("SERVICE_NAME"),
                        rs.getString("X_UNIQUE_ID"),
                        rs.getString("CHANNEL_ID"),
                        rs.getString("REQUEST_ID"),
                        rs.getString("STATUS_CODE_SENT"),
                        rs.getString("DESCRIPTION_SENT"),
                        rs.getString("RAW_PAYLOAD")
                    });
                    cnt++;
                }
                // Update tab title with count
                int tabIdx = -1;
                for (int i = 0; i < monTabs.getTabCount(); i++) {
                    if (monTabs.getTitleAt(i).startsWith("Callback Audit")) {
                        tabIdx = i; break;
                    }
                }
                if (tabIdx >= 0)
                    monTabs.setTitleAt(tabIdx, "Callback Audit (" + cnt + ")");
                if (lblCount != null)
                    lblCount.setText(cnt + " record(s)");
                app.setStatus("Callback audit loaded: " + cnt + " record(s).",
                    CrmAdminTool.CLR_SUCCESS);
            }
        } catch (Exception ex) {
            app.setStatus("Callback audit error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
            CrmAdminTool.LOGGER.log("ERROR",
                "loadCallbackAudit: " + ex.getMessage());
        }
    }

    void refresh() {
        loadDropdowns();
        loadDashboard();
        loadMain();
        loadAction();
        loadRetry();
        loadTriage();
        loadCallbackAudit(null, null, null, null, null);
        String ts = new SimpleDateFormat("HH:mm:ss").format(new Date());
        lblLastRefresh.setText("Last refresh: " + ts);
    }

    private void loadDropdowns() {
        String q1 = app.sql("query.service.names");
        String q2 = app.sql("query.status.list");
        if (q1 == null || q2 == null) return;
        try (Connection con = app.getConnection()) {
            cbService.removeAllItems();
            cbService.addItem("-- All Services --");
            try (PreparedStatement ps = con.prepareStatement(q1);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) cbService.addItem(rs.getString(1));
            }
            cbStatus.removeAllItems();
            cbStatus.addItem("-- All Statuses --");
            try (PreparedStatement ps = con.prepareStatement(q2);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) cbStatus.addItem(rs.getString(1));
            }
        } catch (SQLException ex) {
            app.setStatus("Dropdown error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadDashboard() {
        String q = app.sql("query.dashboard");
        if (q == null) return;
        loadTableData(mdlDash, q, new Object[0]);
    }

    private void loadMain() {
        String q = app.sql("query.main.report");
        if (q == null) return;
        String svc   = getSelected(cbService);
        String sts   = getSelected(cbStatus);
        String from  = tfFromDate.getText().trim().isEmpty()
            ? null : tfFromDate.getText().trim();
        String to    = tfToDate.getText().trim().isEmpty()
            ? null : tfToDate.getText().trim();
        String recId = tfRecordId.getText().trim().isEmpty()
            ? null : tfRecordId.getText().trim();
        Object[] params = {
            svc, svc, sts, sts, from, from, to, to, recId, recId
        };
        loadTableData(mdlMain, q, params);
        monTabs.setTitleAt(1,
            "All Records (" + mdlMain.getRowCount() + ")");
    }

    private void loadAction() {
        String q = app.sql("query.action.needed");
        if (q == null) return;
        loadTableData(mdlAction, q, new Object[0]);
        int cnt = mdlAction.getRowCount();
        monTabs.setTitleAt(2,
            "Action Needed" + (cnt > 0 ? " (" + cnt + ")" : ""));
    }

    private void loadRetry() {
        String q = app.sql("query.retry.queue");
        if (q == null) return;
        loadTableData(mdlRetry, q, new Object[0]);
        monTabs.setTitleAt(3,
            "Retry Queue (" + mdlRetry.getRowCount() + ")");
    }

    private void loadTableData(DefaultTableModel mdl,
                               String q, Object[] params) {
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            for (int i = 0; i < params.length; i++) {
                if (params[i] == null)
                    ps.setNull(i + 1, Types.VARCHAR);
                else
                    ps.setString(i + 1, params[i].toString());
            }
            ResultSet rs = ps.executeQuery();
            ResultSetMetaData meta = rs.getMetaData();
            int cols = meta.getColumnCount();
            mdl.setColumnCount(0);
            for (int i = 1; i <= cols; i++)
                mdl.addColumn(meta.getColumnLabel(i));
            mdl.setRowCount(0);
            while (rs.next()) {
                Object[] row = new Object[cols];
                for (int i = 1; i <= cols; i++)
                    row[i - 1] = rs.getString(i);
                mdl.addRow(row);
            }
            app.setStatus("Loaded " + mdl.getRowCount() + " row(s)",
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void manualRetry(JTable t, DefaultTableModel m) {
        int row = t.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a record first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String logId  = getCol(m, row, "LOG_ID");
        String status = getCol(m, row, "STATUS");
        if (status == null) status = getCol(m, row, "FINAL_STATUS");

        if (logId == null) {
            app.setStatus("LOG_ID not found.", CrmAdminTool.CLR_ERROR);
            return;
        }

        // Block retry on non-eligible statuses
        if (status != null && (
                status.equals("SUCCESS") ||
                status.equals("SENT")    ||
                status.equals("ACK_OK")  ||
                status.equals("DUPLICATE_RECORD"))) {
            JOptionPane.showMessageDialog(this,
                "Record Log ID " + logId + " has status: " + status + "\n\n" +
                "Manual retry is only allowed for:\n" +
                "FAILED, EXHAUSTED, VALIDATION_FAILED,\n" +
                "CRM_REJECTED, RECORD_NOT_FOUND",
                "Not Eligible for Retry",
                JOptionPane.WARNING_MESSAGE);
            app.setStatus("Log ID " + logId +
                " -- status " + status + " not eligible for retry.",
                CrmAdminTool.CLR_WARN);
            return;
        }

        int ok = JOptionPane.showConfirmDialog(this,
            "Queue manual retry for Log ID: " + logId + "?\n" +
            "Current Status: " + status + "\n\n" +
            "Make sure the data issue is fixed first.",
            "Confirm Manual Retry", JOptionPane.YES_NO_OPTION);
        if (ok != JOptionPane.YES_OPTION) return;

        String q = app.sql("query.manual.retry");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, logId);
            int updated = ps.executeUpdate();
            con.commit();
            if (updated > 0) {
                app.setStatus("Retry queued for Log ID: " + logId,
                    CrmAdminTool.CLR_SUCCESS);
                JOptionPane.showMessageDialog(this,
                    "Manual retry queued for Log ID: " + logId + "\n" +
                    "Will run at next RUN_RETRY_JOB execution.",
                    "Queued", JOptionPane.INFORMATION_MESSAGE);
                refresh();
            } else {
                app.setStatus(
                    "Log ID " + logId +
                    " not eligible for retry -- status: " + status,
                    CrmAdminTool.CLR_WARN);
                JOptionPane.showMessageDialog(this,
                    "Log ID " + logId + " could not be queued.\n\n" +
                    "Current Status: " + status + "\n" +
                    "Only FAILED, EXHAUSTED, VALIDATION_FAILED,\n" +
                    "CRM_REJECTED, RECORD_NOT_FOUND are eligible.",
                    "Not Queued",
                    JOptionPane.WARNING_MESSAGE);
            }
        } catch (SQLException ex) {
            app.setStatus("Retry error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void showDetail(JTable t, DefaultTableModel m) {
        int row = t.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a record first.", CrmAdminTool.CLR_WARN);
            return;
        }

        // Collect all column values for this row
        java.util.Map<String,String> data = new java.util.LinkedHashMap<String,String>();
        for (int c = 0; c < m.getColumnCount(); c++) {
            Object v = m.getValueAt(row, c);
            data.put(m.getColumnName(c), v == null ? "" : v.toString());
        }

        String logId  = data.containsKey("LOG_ID")   ? data.get("LOG_ID")   :
                        data.containsKey("AUDIT_ID")  ? data.get("AUDIT_ID") : "—";
        String title  = data.containsKey("LOG_ID")
            ? "Record Detail  —  LOG_ID: " + logId
            : "Callback Audit Detail  —  AUDIT_ID: " + logId;

        // ── Dialog ────────────────────────────────────────────────────────────
        JDialog dlg = new JDialog(
            (Frame) SwingUtilities.getWindowAncestor(this), title, false);
        dlg.setSize(900, 620);
        dlg.setLocationRelativeTo(this);
        dlg.getContentPane().setBackground(CrmAdminTool.CLR_BG);
        dlg.setLayout(new BorderLayout(0, 0));

        // ── Title bar ─────────────────────────────────────────────────────────
        JPanel titleBar = new JPanel(new BorderLayout());
        titleBar.setBackground(CrmAdminTool.CLR_HDR_BG);
        titleBar.setBorder(new EmptyBorder(10, 14, 10, 14));
        JLabel lblTitle = new JLabel(title);
        lblTitle.setFont(new Font("Arial", Font.BOLD, 14));
        lblTitle.setForeground(Color.WHITE);

        // Status badge in title bar
        String status = data.containsKey("STATUS") ? data.get("STATUS") :
                        data.containsKey("FINAL_STATUS") ? data.get("FINAL_STATUS") :
                        data.containsKey("STATUS_CODE_SENT") ? data.get("STATUS_CODE_SENT") : "";
        JLabel lblStatus = new JLabel(" " + status + " ");
        lblStatus.setFont(new Font("Arial", Font.BOLD, 12));
        lblStatus.setOpaque(true);
        lblStatus.setBorder(new EmptyBorder(3, 8, 3, 8));
        if (status.contains("SUCCESS") || status.equals("CB_0000") || status.equals("ACK_OK")) {
            lblStatus.setBackground(new Color(55,87,35));
            lblStatus.setForeground(Color.WHITE);
        } else if (status.contains("FAILED") || status.contains("EXHAUSTED")
                || status.contains("CB_1002")) {
            lblStatus.setBackground(new Color(192,0,0));
            lblStatus.setForeground(Color.WHITE);
        } else if (status.contains("SENT") || status.contains("PENDING")) {
            lblStatus.setBackground(new Color(31,56,100));
            lblStatus.setForeground(Color.WHITE);
        } else {
            lblStatus.setBackground(new Color(197,90,17));
            lblStatus.setForeground(Color.WHITE);
        }
        titleBar.add(lblTitle,  BorderLayout.WEST);
        titleBar.add(lblStatus, BorderLayout.EAST);
        dlg.add(titleBar, BorderLayout.NORTH);

        // ── Tabs ──────────────────────────────────────────────────────────────
        JTabbedPane detailTabs = new JTabbedPane();
        detailTabs.setFont(CrmAdminTool.FONT_LABEL);
        detailTabs.setBackground(CrmAdminTool.CLR_BG);

        // Helper — make a read-only text area
        // Tab 1: Summary — key fields in a clean table
        JPanel sumPanel = new JPanel(new BorderLayout());
        sumPanel.setBackground(Color.WHITE);
        sumPanel.setBorder(new EmptyBorder(10,10,10,10));

        String[] summaryKeys = {
            "LOG_ID","AUDIT_ID","SERVICE_NAME","SOURCE_RECORD_ID",
            "FINAL_STATUS","STATUS_CODE_SENT","X_UNIQUE_ID",
            "ERROR_CODE","CRM_REFERENCE_NO","REQUEST_ID",
            "SENT_DATE","RECEIVED_AT","CALLBACK_DATE","CREATED_DATE",
            "RETRY","RETRY_COUNT","MANUAL_RETRY","EXECUTED_BY",
            "CHANNEL_ID","ACTION","ACTION_NEEDED"
        };
        DefaultTableModel sumModel = new DefaultTableModel(
            new String[]{"Field","Value"}, 0) {
            public boolean isCellEditable(int r, int c) { return false; }
        };
        for (String k : summaryKeys) {
            if (data.containsKey(k) && !data.get(k).isEmpty())
                sumModel.addRow(new Object[]{k, data.get(k)});
        }
        JTable sumTable = new JTable(sumModel);
        sumTable.setFont(CrmAdminTool.FONT_LABEL);
        sumTable.setRowHeight(22);
        sumTable.setShowGrid(true);
        sumTable.setGridColor(new Color(220,230,240));
        sumTable.getColumnModel().getColumn(0).setPreferredWidth(180);
        sumTable.getColumnModel().getColumn(0).setMaxWidth(220);
        sumTable.getColumnModel().getColumn(1).setPreferredWidth(600);
        // Bold field name column
        sumTable.getColumnModel().getColumn(0)
            .setCellRenderer(new javax.swing.table.DefaultTableCellRenderer() {
                public java.awt.Component getTableCellRendererComponent(
                        JTable tbl, Object v, boolean sel,
                        boolean foc, int r, int c) {
                    super.getTableCellRendererComponent(tbl,v,sel,foc,r,c);
                    setFont(new Font("Arial", Font.BOLD, 12));
                    setBackground(new Color(240,246,255));
                    setForeground(new Color(31,56,100));
                    setBorder(new EmptyBorder(2,8,2,8));
                    return this;
                }
            });
        sumTable.getTableHeader().setFont(
            new Font("Arial", Font.BOLD, 12));
        sumTable.getTableHeader().setBackground(CrmAdminTool.CLR_HDR_BG);
        sumTable.getTableHeader().setForeground(Color.WHITE);
        sumPanel.add(new JScrollPane(sumTable), BorderLayout.CENTER);
        detailTabs.addTab("Summary", sumPanel);

        // Tab 2: Request Payload
        String reqPayload = data.containsKey("DATA_SENT")    ? data.get("DATA_SENT") :
                            data.containsKey("RAW_PAYLOAD")   ? data.get("RAW_PAYLOAD") : "";
        detailTabs.addTab("Request Payload", makeTextTab(
            reqPayload.isEmpty() ? "(No request payload available)" : reqPayload,
            new Color(240,248,255)));

        // Tab 3: CRM Response / Callback
        StringBuilder respSb = new StringBuilder();
        appendIfPresent(respSb, "CRM Response",      data.get("CRM_RESPONSE"));
        appendIfPresent(respSb, "Failed Fields",     data.get("FAILED_FIELDS"));
        appendIfPresent(respSb, "CRM Reference No",  data.get("CRM_REFERENCE_NO"));
        appendIfPresent(respSb, "Description Sent",  data.get("DESCRIPTION_SENT"));
        appendIfPresent(respSb, "Status Code Sent",  data.get("STATUS_CODE_SENT"));
        appendIfPresent(respSb, "X Unique ID",       data.get("X_UNIQUE_ID"));
        appendIfPresent(respSb, "Channel",           data.get("CHANNEL_ID"));
        appendIfPresent(respSb, "Request ID",        data.get("REQUEST_ID"));
        appendIfPresent(respSb, "Callback Date",     data.get("CALLBACK_DATE"));
        appendIfPresent(respSb, "Received At",       data.get("RECEIVED_AT"));
        detailTabs.addTab("CRM Response", makeTextTab(
            respSb.length() == 0 ? "(No callback response yet)" : respSb.toString(),
            new Color(240,255,245)));

        // Tab 4: Error Detail
        StringBuilder errSb = new StringBuilder();
        appendIfPresent(errSb, "Error Code",        data.get("ERROR_CODE"));
        appendIfPresent(errSb, "Error Message",     data.get("ERROR_DETAIL"));
        appendIfPresent(errSb, "Failed Fields",     data.get("FAILED_FIELDS"));
        appendIfPresent(errSb, "Final Status",      data.get("FINAL_STATUS"));
        appendIfPresent(errSb, "Retry Count",       data.get("RETRY"));
        appendIfPresent(errSb, "Executed By",       data.get("EXECUTED_BY"));
        detailTabs.addTab("Error Detail", makeTextTab(
            errSb.length() == 0 ? "(No error information)" : errSb.toString(),
            new Color(255,245,245)));

        // Tab 5: All Fields (raw dump)
        StringBuilder allSb = new StringBuilder();
        for (java.util.Map.Entry<String,String> e : data.entrySet()) {
            if (!e.getValue().isEmpty()) {
                allSb.append(String.format("%-30s : %s%n",
                    e.getKey(), e.getValue()));
            }
        }
        detailTabs.addTab("All Fields", makeTextTab(
            allSb.toString(), new Color(250,250,250)));

        dlg.add(detailTabs, BorderLayout.CENTER);

        // ── Bottom buttons ────────────────────────────────────────────────────
        JPanel bot = new JPanel(new FlowLayout(FlowLayout.RIGHT, 10, 8));
        bot.setBackground(CrmAdminTool.CLR_BG);
        bot.setBorder(new MatteBorder(1,0,0,0,CrmAdminTool.CLR_BORDER));

        JButton btnCopy = CrmAdminTool.mkBtn("Copy to Clipboard", CrmAdminTool.BTN_BLUE);
        JButton btnClose= CrmAdminTool.mkBtn("Close",             CrmAdminTool.BTN_GREY);

        btnCopy.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                StringBuilder all = new StringBuilder();
                all.append("=== ").append(title).append(" ===\n\n");
                for (java.util.Map.Entry<String,String> en : data.entrySet()) {
                    if (!en.getValue().isEmpty())
                        all.append(String.format("%-30s : %s%n",
                            en.getKey(), en.getValue()));
                }
                java.awt.datatransfer.StringSelection ss =
                    new java.awt.datatransfer.StringSelection(all.toString());
                java.awt.Toolkit.getDefaultToolkit()
                    .getSystemClipboard().setContents(ss, null);
                app.setStatus("Detail copied to clipboard.", CrmAdminTool.CLR_SUCCESS);
            }
        });
        btnClose.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { dlg.dispose(); }
        });

        bot.add(btnCopy); bot.add(btnClose);
        dlg.add(bot, BorderLayout.SOUTH);
        dlg.setVisible(true);
    }

    private JPanel makeTextTab(String content, Color bg) {
        JTextArea ta = new JTextArea(content);
        ta.setEditable(false);
        ta.setFont(new Font("Courier New", Font.PLAIN, 12));
        ta.setForeground(new Color(30,30,30));
        ta.setBackground(bg);
        ta.setLineWrap(true);
        ta.setWrapStyleWord(true);
        ta.setBorder(new EmptyBorder(10,12,10,12));
        JPanel p = new JPanel(new BorderLayout());
        p.add(new JScrollPane(ta), BorderLayout.CENTER);
        return p;
    }

    private void appendIfPresent(StringBuilder sb, String label, String val) {
        if (val != null && !val.trim().isEmpty()) {
            sb.append("=== ").append(label).append(" ===\n")
              .append(val.trim()).append("\n\n");
        }
    }

    private void clearFilters() {
        cbService.setSelectedIndex(0);
        cbStatus .setSelectedIndex(0);
        SimpleDateFormat sdf = new SimpleDateFormat("dd-MMM-yy");
        tfFromDate.setText(sdf.format(
            new Date(System.currentTimeMillis() - 7L * 86400000L)));
        tfToDate.setText(sdf.format(new Date()));
        tfRecordId.setText("");
        loadMain();
    }

    private String getSelected(JComboBox cb) {
        String s = (String) cb.getSelectedItem();
        return (s == null || s.startsWith("--")) ? null : s;
    }

    private String getCol(DefaultTableModel m, int row, String col) {
        for (int c = 0; c < m.getColumnCount(); c++)
            if (m.getColumnName(c).equalsIgnoreCase(col))
                return String.valueOf(m.getValueAt(row, c));
        return null;
    }

    static class ActionNeededRenderer extends DefaultTableCellRenderer {
        public Component getTableCellRendererComponent(
                JTable t, Object v, boolean sel,
                boolean foc, int r, int c) {
            super.getTableCellRendererComponent(t, v, sel, foc, r, c);
            int cnt = 0;
            try { cnt = Integer.parseInt(
                v == null ? "0" : v.toString()); }
            catch (NumberFormatException ignored) {}
            setFont(new Font("Arial", Font.BOLD, 13));
            setForeground(cnt > 0
                ? CrmAdminTool.CLR_ERROR : CrmAdminTool.CLR_SUCCESS);
            setBackground(sel ? CrmAdminTool.CLR_SEL
                : (r % 2 == 0 ? Color.WHITE : CrmAdminTool.CLR_ROW_ALT));
            setBorder(new EmptyBorder(0, 6, 0, 6));
            return this;
        }
    }
}

// =============================================================================
//  TAB 7: SCRIPT DOWNLOAD
// =============================================================================
class ScriptTab extends JPanel {

    private CrmAdminTool app;
    private JTextArea    taOutput;
    private JComboBox    cbSection;

    ScriptTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        JPanel top = CrmAdminTool.mkPanel(new FlowLayout(
            FlowLayout.LEFT, 10, 8));
        top.setBorder(new CompoundBorder(
            new MatteBorder(0, 0, 1, 0, CrmAdminTool.CLR_BORDER),
            new EmptyBorder(4, 8, 4, 8)));

        cbSection = CrmAdminTool.mkCombo(new String[]{
            "All Scripts",
            "Table DDL",
            "Sequence DDL",
            "Config Data (Registry + Mappings + Error Codes)",
            "Scheduler Jobs",
            "Watermark Init"
        });

        JButton btnGenerate = CrmAdminTool.mkBtn("Generate Script",
            CrmAdminTool.BTN_BLUE);
        JButton btnSave     = CrmAdminTool.mkBtn("Save to File",
            CrmAdminTool.BTN_GREEN);
        JButton btnClear    = CrmAdminTool.mkBtn("Clear",
            CrmAdminTool.BTN_GREY);

        btnGenerate.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { generate(); }
        });
        btnSave    .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { saveToFile(); }
        });
        btnClear   .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                taOutput.setText("");
            }
        });

        top.add(CrmAdminTool.mkLabel("Section:"));
        top.add(cbSection);
        top.add(btnGenerate);
        top.add(btnSave);
        top.add(btnClear);
        add(top, BorderLayout.NORTH);

        taOutput = new JTextArea();
        taOutput.setFont(new Font("Courier New", Font.PLAIN, 12));
        taOutput.setForeground(CrmAdminTool.CLR_TEXT);
        taOutput.setBackground(Color.WHITE);
        taOutput.setEditable(false);
        taOutput.setLineWrap(false);

        JScrollPane sp = new JScrollPane(taOutput);
        sp.setBorder(new LineBorder(CrmAdminTool.CLR_BORDER, 1));
        add(sp, BorderLayout.CENTER);

        JLabel hint = new JLabel(
            "  Generate scripts to deploy configuration to SIT/UAT/PROD");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        hint.setBorder(new EmptyBorder(4, 8, 4, 8));
        add(hint, BorderLayout.SOUTH);
    }

    void refresh() {}

    private void generate() {
        String section = (String) cbSection.getSelectedItem();
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================================\n");
        sb.append("-- CRM Integration Script\n");
        sb.append("-- Generated: ").append(
            new SimpleDateFormat("DD-MMM-YY HH:mm:ss").format(new Date()))
          .append("\n");
        sb.append("-- Section: ").append(section).append("\n");
        sb.append("-- ===========================================\n\n");
        sb.append("SET DEFINE OFF\n");
        sb.append("SET SERVEROUTPUT ON SIZE UNLIMITED\n\n");

        try (Connection con = app.getConnection()) {
            if ("All Scripts".equals(section)
                    || "Config Data (Registry + Mappings + Error Codes)"
                        .equals(section)) {
                sb.append(generateRegistryScript(con));
                sb.append(generateMappingScript(con));
                sb.append(generateErrorCodeScript(con));
            }
            if ("All Scripts".equals(section)
                    || "Scheduler Jobs".equals(section)) {
                sb.append(generateSchedulerScript());
            }
            if ("All Scripts".equals(section)
                    || "Watermark Init".equals(section)) {
                sb.append(generateWatermarkScript(con));
            }
            if ("All Scripts".equals(section)
                    || "Table DDL".equals(section)) {
                sb.append(generateTableDDLNote());
            }
            if ("All Scripts".equals(section)
                    || "Sequence DDL".equals(section)) {
                sb.append(generateSequenceDDLNote());
            }
        } catch (SQLException ex) {
            sb.append("-- ERROR generating script: ")
              .append(ex.getMessage()).append("\n");
        }

        taOutput.setText(sb.toString());
        taOutput.setCaretPosition(0);
        app.setStatus("Script generated.", CrmAdminTool.CLR_SUCCESS);
    }

    private String generateRegistryScript(Connection con)
            throws SQLException {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- SERVICE REGISTRY\n");
        sb.append("-- ===========================\n");
        String q = app.sql("query.registry.list");
        if (q == null) return "";
        try (PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                sb.append("MERGE INTO CRM_MPM_API_REGISTRY r\n");
                sb.append("USING (SELECT '")
                  .append(rs.getString(1)).append("' AS sn FROM DUAL) s\n");
                sb.append("ON (r.SERVICE_NAME = s.sn)\n");
                sb.append("WHEN MATCHED THEN UPDATE SET\n");
                sb.append("    ENTITY_NAME='").append(safe(rs.getString(2)))
                  .append("',\n");
                sb.append("    OPERATION_TYPE='").append(safe(rs.getString(3)))
                  .append("',\n");
                sb.append("    SOURCE_TYPE='").append(safe(rs.getString(4)))
                  .append("',\n");
                sb.append("    SOURCE_VIEW='").append(safe(rs.getString(5)))
                  .append("',\n");
                sb.append("    SOURCE_FILTER_COL=")
                  .append(rs.getString(6) == null
                      ? "NULL" : "'" + safe(rs.getString(6)) + "'")
                  .append(",\n");
                sb.append("    RECORD_TYPE='").append(safe(rs.getString(7)))
                  .append("',\n");
                sb.append("    RECORD_ACTION='").append(safe(rs.getString(8)))
                  .append("',\n");
                sb.append("    HAS_CALLBACK='").append(safe(rs.getString(9)))
                  .append("',\n");
                sb.append("    EXECUTION_ORDER=").append(safe(rs.getString(10)))
                  .append(",\n");
                sb.append("    BATCH_SIZE=").append(safe(rs.getString(11)))
                  .append(",\n");
                sb.append("    IS_ACTIVE='").append(safe(rs.getString(12)))
                  .append("'\n");
                sb.append("WHEN NOT MATCHED THEN INSERT (\n");
                sb.append("    SERVICE_NAME,ENTITY_NAME,OPERATION_TYPE,");
                sb.append("SOURCE_TYPE,SOURCE_VIEW,SOURCE_FILTER_COL,\n");
                sb.append("    RECORD_TYPE,RECORD_ACTION,HAS_CALLBACK,");
                sb.append("EXECUTION_ORDER,BATCH_SIZE,IS_ACTIVE)\n");
                sb.append("VALUES ('").append(rs.getString(1))
                  .append("','").append(safe(rs.getString(2)))
                  .append("','").append(safe(rs.getString(3)))
                  .append("','").append(safe(rs.getString(4)))
                  .append("','").append(safe(rs.getString(5)))
                  .append("',")
                  .append(rs.getString(6) == null
                      ? "NULL" : "'" + safe(rs.getString(6)) + "'")
                  .append(",\n    '").append(safe(rs.getString(7)))
                  .append("','").append(safe(rs.getString(8)))
                  .append("','").append(safe(rs.getString(9)))
                  .append("',").append(safe(rs.getString(10)))
                  .append(",").append(safe(rs.getString(11)))
                  .append(",'").append(safe(rs.getString(12)))
                  .append("');\n\n");
            }
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    private String generateMappingScript(Connection con)
            throws SQLException {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- FIELD MAPPINGS\n");
        sb.append("-- ===========================\n");
        String q = app.sql("query.mapping.all");
        if (q == null) return "";
        try (PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                sb.append("MERGE INTO CRM_MPM_API_FIELD_MAPPING m\n");
                sb.append("USING (SELECT '").append(rs.getString(2))
                  .append("' AS sn, '").append(rs.getString(4))
                  .append("' AS sc FROM DUAL) s\n");
                sb.append("ON (m.SERVICE_NAME=s.sn AND m.SOURCE_COLUMN=s.sc)\n");
                sb.append("WHEN MATCHED THEN UPDATE SET\n");
                sb.append("    FIELD_ORDER=").append(safe(rs.getString(3)))
                  .append(", JSON_FIELD='").append(safe(rs.getString(5)))
                  .append("',\n");
                sb.append("    DATA_TYPE='").append(safe(rs.getString(6)))
                  .append("', DATE_FORMAT=")
                  .append(rs.getString(7) == null
                      ? "NULL" : "'" + safe(rs.getString(7)) + "'")
                  .append(",\n");
                sb.append("    IS_ACTIVE='").append(safe(rs.getString(9)))
                  .append("'\n");
                sb.append("WHEN NOT MATCHED THEN INSERT (\n");
                sb.append("    SERVICE_NAME,FIELD_ORDER,SOURCE_COLUMN,");
                sb.append("JSON_FIELD,DATA_TYPE,DATE_FORMAT,IS_ACTIVE)\n");
                sb.append("VALUES ('").append(rs.getString(2))
                  .append("',").append(safe(rs.getString(3)))
                  .append(",'").append(safe(rs.getString(4)))
                  .append("','").append(safe(rs.getString(5)))
                  .append("','").append(safe(rs.getString(6)))
                  .append("',")
                  .append(rs.getString(7) == null
                      ? "NULL" : "'" + safe(rs.getString(7)) + "'")
                  .append(",'").append(safe(rs.getString(9)))
                  .append("');\n\n");
            }
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    private String generateErrorCodeScript(Connection con)
            throws SQLException {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- ERROR CODE MASTER\n");
        sb.append("-- ===========================\n");
        String q = app.sql("query.errorcode.list");
        if (q == null) return "";
        try (PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                sb.append("MERGE INTO CRM_MPM_ERROR_CODE_MASTER e\n");
                sb.append("USING (SELECT '").append(rs.getString(1))
                  .append("' AS ec FROM DUAL) s\n");
                sb.append("ON (e.ERROR_CODE = s.ec)\n");
                sb.append("WHEN MATCHED THEN UPDATE SET\n");
                sb.append("    ERROR_CATEGORY='").append(safe(rs.getString(2)))
                  .append("', ERROR_DESCRIPTION='")
                  .append(safe(rs.getString(3)))
                  .append("', IS_RETRYABLE='")
                  .append(safe(rs.getString(4))).append("'\n");
                sb.append("WHEN NOT MATCHED THEN INSERT (")
                  .append("ERROR_CODE,ERROR_CATEGORY,")
                  .append("ERROR_DESCRIPTION,IS_RETRYABLE)\n");
                sb.append("VALUES ('").append(rs.getString(1))
                  .append("','").append(safe(rs.getString(2)))
                  .append("','").append(safe(rs.getString(3)))
                  .append("','").append(safe(rs.getString(4)))
                  .append("');\n\n");
            }
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    private String generateSchedulerScript() {
        return
            "-- ===========================\n" +
            "-- SCHEDULER JOBS\n" +
            "-- ===========================\n" +
            "-- Outbound 6AM\n" +
            "BEGIN\n" +
            "  DBMS_SCHEDULER.CREATE_JOB(\n" +
            "    job_name=>'CRM_MPM_OUTBOUND_6AM',\n" +
            "    job_type=>'PLSQL_BLOCK',\n" +
            "    job_action=>'BEGIN " +
            "PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',\n" +
            "    repeat_interval=>" +
            "'FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0',\n" +
            "    enabled=>TRUE);\n" +
            "END;\n/\n" +
            "-- Outbound 10AM\n" +
            "BEGIN\n" +
            "  DBMS_SCHEDULER.CREATE_JOB(\n" +
            "    job_name=>'CRM_MPM_OUTBOUND_10AM',\n" +
            "    job_type=>'PLSQL_BLOCK',\n" +
            "    job_action=>'BEGIN " +
            "PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',\n" +
            "    repeat_interval=>" +
            "'FREQ=DAILY;BYHOUR=10;BYMINUTE=0;BYSECOND=0',\n" +
            "    enabled=>TRUE);\n" +
            "END;\n/\n" +
            "-- Outbound 2PM\n" +
            "BEGIN\n" +
            "  DBMS_SCHEDULER.CREATE_JOB(\n" +
            "    job_name=>'CRM_MPM_OUTBOUND_2PM',\n" +
            "    job_type=>'PLSQL_BLOCK',\n" +
            "    job_action=>'BEGIN " +
            "PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',\n" +
            "    repeat_interval=>" +
            "'FREQ=DAILY;BYHOUR=14;BYMINUTE=0;BYSECOND=0',\n" +
            "    enabled=>TRUE);\n" +
            "END;\n/\n" +
            "-- Outbound 5PM\n" +
            "BEGIN\n" +
            "  DBMS_SCHEDULER.CREATE_JOB(\n" +
            "    job_name=>'CRM_MPM_OUTBOUND_5PM',\n" +
            "    job_type=>'PLSQL_BLOCK',\n" +
            "    job_action=>'BEGIN " +
            "PKG_CRM_INTEGRATION.RUN_OUTBOUND_JOB; END;',\n" +
            "    repeat_interval=>" +
            "'FREQ=DAILY;BYHOUR=17;BYMINUTE=0;BYSECOND=0',\n" +
            "    enabled=>TRUE);\n" +
            "END;\n/\n" +
            "-- Retry Job every 30 min\n" +
            "BEGIN\n" +
            "  DBMS_SCHEDULER.CREATE_JOB(\n" +
            "    job_name=>'CRM_MPM_RETRY_JOB',\n" +
            "    job_type=>'PLSQL_BLOCK',\n" +
            "    job_action=>'BEGIN " +
            "PKG_CRM_INTEGRATION.RUN_RETRY_JOB; END;',\n" +
            "    repeat_interval=>'FREQ=MINUTELY;INTERVAL=30',\n" +
            "    enabled=>TRUE);\n" +
            "END;\n/\n" +
            "-- Timeout Job every hour\n" +
            "BEGIN\n" +
            "  DBMS_SCHEDULER.CREATE_JOB(\n" +
            "    job_name=>'CRM_MPM_TIMEOUT_JOB',\n" +
            "    job_type=>'PLSQL_BLOCK',\n" +
            "    job_action=>'BEGIN " +
            "PKG_CRM_INTEGRATION.RUN_TIMEOUT_JOB; END;',\n" +
            "    repeat_interval=>'FREQ=HOURLY;INTERVAL=1',\n" +
            "    enabled=>TRUE);\n" +
            "END;\n/\n" +
            "COMMIT;\n\n";
    }

    private String generateWatermarkScript(Connection con)
            throws SQLException {
        StringBuilder sb = new StringBuilder();
        sb.append("-- ===========================\n");
        sb.append("-- WATERMARK INIT\n");
        sb.append("-- (Insert watermark rows for new environment)\n");
        sb.append("-- ===========================\n");
        String q = app.sql("query.service.names");
        if (q == null) return "";
        try (PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String svc = rs.getString(1);
                sb.append("INSERT INTO CRM_MPM_API_WATERMARK\n");
                sb.append("    (SERVICE_NAME, LAST_PROCESSED_TS,\n");
                sb.append("     LAST_RUN_DATE, RECORDS_PROCESSED)\n");
                sb.append("SELECT '").append(svc)
                  .append("', NULL, NULL, 0 FROM DUAL\n");
                sb.append("WHERE NOT EXISTS (\n");
                sb.append("    SELECT 1 FROM CRM_MPM_API_WATERMARK\n");
                sb.append("    WHERE SERVICE_NAME = '")
                  .append(svc).append("');\n\n");
            }
        }
        sb.append("COMMIT;\n\n");
        return sb.toString();
    }

    private String generateTableDDLNote() {
        return
            "-- ===========================\n" +
            "-- TABLE DDL\n" +
            "-- Use DBMS_METADATA to extract from source DB:\n" +
            "-- ===========================\n" +
            "SELECT DBMS_METADATA.GET_DDL('TABLE',TABLE_NAME)\n" +
            "FROM USER_TABLES\n" +
            "WHERE TABLE_NAME LIKE 'CRM_MPM_%'\n" +
            "ORDER BY TABLE_NAME;\n\n";
    }

    private String generateSequenceDDLNote() {
        return
            "-- ===========================\n" +
            "-- SEQUENCE DDL\n" +
            "-- Use DBMS_METADATA to extract from source DB:\n" +
            "-- ===========================\n" +
            "SELECT DBMS_METADATA.GET_DDL('SEQUENCE',SEQUENCE_NAME)\n" +
            "FROM USER_SEQUENCES\n" +
            "WHERE SEQUENCE_NAME LIKE 'SEQ_CRM%'\n" +
            "ORDER BY SEQUENCE_NAME;\n\n";
    }

    private void saveToFile() {
        String content = taOutput.getText();
        if (content.trim().isEmpty()) {
            app.setStatus("Nothing to save. Generate script first.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        JFileChooser fc = new JFileChooser();
        String ts = new SimpleDateFormat("yyyyMMdd_HHmmss")
            .format(new Date());
        fc.setSelectedFile(
            new java.io.File("CRM_Script_" + ts + ".sql"));
        int result = fc.showSaveDialog(this);
        if (result == JFileChooser.APPROVE_OPTION) {
            java.io.File file = fc.getSelectedFile();
            try (PrintWriter pw = new PrintWriter(
                    new FileWriter(file))) {
                pw.print(content);
                app.setStatus("Script saved: " + file.getName(),
                    CrmAdminTool.CLR_SUCCESS);
            } catch (IOException ex) {
                app.setStatus("Save error: " + ex.getMessage(),
                    CrmAdminTool.CLR_ERROR);
            }
        }
    }

    private String safe(String s) {
        if (s == null) return "";
        return s.replace("'", "''");
    }
}

// =============================================================================
//  TAB 8: SCHEDULER MANAGER
// =============================================================================
class SchedulerTab extends JPanel {

    private CrmAdminTool app;

    // -- Job list table
    private JTable            tblJobs;
    private DefaultTableModel mdlJobs;

    // -- Job history table
    private JTable            tblHistory;
    private DefaultTableModel mdlHistory;

    // -- Add job form
    private JTextField  tfJobName, tfJobAction, tfInterval;
    private JComboBox   cbJobType, cbFreq;

    SchedulerTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        // Split: top = job list + buttons, bottom = history
        JSplitPane sp = new JSplitPane(JSplitPane.VERTICAL_SPLIT,
            buildTopPanel(), buildHistoryPanel());
        sp.setDividerLocation(340);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        add(sp, BorderLayout.CENTER);
    }

    // -- Top: job list + action buttons + add form
    private JPanel buildTopPanel() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(10, 10));
        p.setBorder(new EmptyBorder(10, 10, 5, 10));

        // Left: job list
        JPanel listPanel = CrmAdminTool.mkPanel(new BorderLayout(0, 6));

        JLabel lbl = new JLabel("Scheduler Jobs");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        listPanel.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Job Name", "Enabled", "State",
            "Repeat Interval", "Next Run", "Last Run", "Comments"
        };
        mdlJobs = CrmAdminTool.mkModel(cols);
        tblJobs = CrmAdminTool.mkTable(mdlJobs);
        tblJobs.getColumnModel().getColumn(1)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());
        tblJobs.getColumnModel().getColumn(2)
            .setCellRenderer(new StateRenderer());

        int[] w = {220, 60, 80, 220, 130, 130, 200};
        for (int i = 0; i < w.length; i++)
            tblJobs.getColumnModel().getColumn(i).setPreferredWidth(w[i]);

        tblJobs.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                if (e.getClickCount() == 2) loadJobHistory();
            }
        });

        listPanel.add(CrmAdminTool.mkScroll(tblJobs), BorderLayout.CENTER);

        // Action buttons
        JPanel btnPanel = new JPanel(new FlowLayout(
            FlowLayout.LEFT, 8, 6));
        btnPanel.setBackground(CrmAdminTool.CLR_BG);
        btnPanel.setBorder(new MatteBorder(
            1, 0, 0, 0, CrmAdminTool.CLR_BORDER));

        JButton btnRefresh  = CrmAdminTool.mkBtn("Refresh",
            CrmAdminTool.BTN_BLUE);
        JButton btnEnable   = CrmAdminTool.mkBtn("Enable",
            CrmAdminTool.BTN_GREEN);
        JButton btnDisable  = CrmAdminTool.mkBtn("Disable",
            CrmAdminTool.BTN_RED);
        JButton btnRunNow   = CrmAdminTool.mkBtn("Run Now",
            CrmAdminTool.BTN_ORANGE);
        JButton btnHistory  = CrmAdminTool.mkBtn("View History",
            CrmAdminTool.BTN_GREY);
        JButton btnRemove   = CrmAdminTool.mkBtn("Remove Job",
            CrmAdminTool.BTN_RED);
        JButton btnChange   = CrmAdminTool.mkBtn("Change Schedule",
            CrmAdminTool.BTN_ORANGE);

        btnRefresh .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { refresh(); }
        });
        btnEnable  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                setJobEnabled(true);
            }
        });
        btnDisable .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                setJobEnabled(false);
            }
        });
        btnRunNow  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { runNow(); }
        });
        btnHistory .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                loadJobHistory();
            }
        });
        btnRemove  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { removeJob(); }
        });
        btnChange  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                changeSchedule();
            }
        });

        btnPanel.add(btnRefresh);
        btnPanel.add(btnEnable);
        btnPanel.add(btnDisable);
        btnPanel.add(btnRunNow);
        btnPanel.add(btnHistory);
        btnPanel.add(btnChange);
        btnPanel.add(btnRemove);

        listPanel.add(btnPanel, BorderLayout.SOUTH);

        // Right: add new job form
        JPanel formPanel = buildAddJobForm();

        JSplitPane sp2 = new JSplitPane(
            JSplitPane.HORIZONTAL_SPLIT,
            listPanel, formPanel);
        sp2.setDividerLocation(620);
        sp2.setBorder(null);
        sp2.setBackground(CrmAdminTool.CLR_BG);

        p.add(sp2, BorderLayout.CENTER);
        return p;
    }

    private JPanel buildAddJobForm() {
        JPanel outer = CrmAdminTool.mkPanel(new BorderLayout());
        outer.setBorder(new EmptyBorder(0, 6, 0, 0));

        JPanel form = CrmAdminTool.mkFormPanel();
        GridBagConstraints gc = CrmAdminTool.mkGc();

        CrmAdminTool.addSectionLabel(form, gc, 0, "Add New Job");

        tfJobName   = CrmAdminTool.mkField(180);
        cbJobType   = CrmAdminTool.mkCombo(
            new String[]{"PLSQL_BLOCK","STORED_PROCEDURE"});
        tfJobAction = CrmAdminTool.mkField(180);
        cbFreq      = CrmAdminTool.mkCombo(new String[]{
            "FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0",
            "FREQ=DAILY;BYHOUR=10;BYMINUTE=0;BYSECOND=0",
            "FREQ=DAILY;BYHOUR=14;BYMINUTE=0;BYSECOND=0",
            "FREQ=DAILY;BYHOUR=17;BYMINUTE=0;BYSECOND=0",
            "FREQ=MINUTELY;INTERVAL=30",
            "FREQ=HOURLY;INTERVAL=1",
            "FREQ=DAILY;BYHOUR=23;BYMINUTE=0;BYSECOND=0",
            "FREQ=DAILY;BYHOUR=4;BYMINUTE=0;BYSECOND=0",
            "Custom"
        });
        tfInterval  = CrmAdminTool.mkField(180);

        cbFreq.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                String sel = (String) cbFreq.getSelectedItem();
                if ("Custom".equals(sel)) {
                    tfInterval.setEnabled(true);
                    tfInterval.setText("");
                } else {
                    tfInterval.setEnabled(false);
                    tfInterval.setText(sel);
                }
            }
        });
        tfInterval.setEnabled(false);
        tfInterval.setText(
            "FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0");

        CrmAdminTool.addFormRow(form, gc, 1, "Job Name *",    tfJobName);
        CrmAdminTool.addFormRow(form, gc, 2, "Job Type",      cbJobType);
        CrmAdminTool.addFormRow(form, gc, 3, "Job Action *",  tfJobAction);
        CrmAdminTool.addFormRow(form, gc, 4, "Schedule",      cbFreq);
        CrmAdminTool.addFormRow(form, gc, 5, "Custom Interval",tfInterval);

        gc.gridx = 0; gc.gridy = 6; gc.gridwidth = 2;
        JLabel hint = new JLabel(
            "Action e.g: BEGIN PKG_CRM_INTEGRATION.RUN_RETRY_JOB; END;");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        form.add(hint, gc);

        gc.gridy = 7; gc.gridwidth = 2;
        JPanel btns = new JPanel(new GridLayout(1, 2, 8, 0));
        btns.setBackground(CrmAdminTool.CLR_PANEL);
        btns.setBorder(new EmptyBorder(8, 0, 0, 0));
        JButton btnAdd   = CrmAdminTool.mkBtn("Add Job",
            CrmAdminTool.BTN_BLUE);
        JButton btnClear = CrmAdminTool.mkBtn("Clear",
            CrmAdminTool.BTN_GREY);
        btnAdd  .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { addJob(); }
        });
        btnClear.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { clearForm(); }
        });
        btns.add(btnAdd); btns.add(btnClear);
        form.add(btns, gc);

        outer.add(form, BorderLayout.NORTH);
        return outer;
    }

    // -- Bottom: job run history
    private JPanel buildHistoryPanel() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 6));
        p.setBorder(new EmptyBorder(5, 10, 10, 10));

        JLabel lbl = new JLabel(
            "Job Run History (double-click a job above to load)");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Log ID", "Job Name", "Status",
            "Run Time", "Operation",
            "User Name", "Additional Info"
        };
        mdlHistory = CrmAdminTool.mkModel(cols);
        tblHistory = CrmAdminTool.mkTable(mdlHistory);
        tblHistory.getColumnModel().getColumn(2)
            .setCellRenderer(new RunStatusRenderer());

        int[] w = {70, 220, 80, 130, 100, 100, 300};
        for (int i = 0; i < w.length; i++)
            tblHistory.getColumnModel().getColumn(i)
                .setPreferredWidth(w[i]);

        p.add(CrmAdminTool.mkScroll(tblHistory), BorderLayout.CENTER);
        return p;
    }

    // =========================================================================
    //  DB OPERATIONS
    // =========================================================================

    void refresh() {
        String q = app.sql("query.scheduler.list");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            mdlJobs.setRowCount(0);
            while (rs.next()) {
                mdlJobs.addRow(new Object[]{
                    rs.getString(1), rs.getString(2),
                    rs.getString(3), rs.getString(4),
                    rs.getString(5), rs.getString(6),
                    rs.getString(7)
                });
            }
            app.updateTabTitle(7,
                "Scheduler (" + mdlJobs.getRowCount() + ")");
            app.setStatus("Scheduler jobs loaded: " +
                mdlJobs.getRowCount(), CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("Load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void setJobEnabled(boolean enable) {
        int row = tblJobs.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a job first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String jobName = (String) mdlJobs.getValueAt(row, 0);
        String action  = enable ? "ENABLE" : "DISABLE";

        int ok = JOptionPane.showConfirmDialog(this,
            action + " job: " + jobName + "?",
            "Confirm", JOptionPane.YES_NO_OPTION);
        if (ok != JOptionPane.YES_OPTION) return;

        String sql =
            "BEGIN\n" +
            "    DBMS_SCHEDULER." + action + "(:jobname);\n" +
            "END;";
        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {
            cs.setString("jobname", jobName);
            cs.execute();
            con.commit();
            app.setStatus(jobName + " " + action + "D successfully.",
                CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus(action + " error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void runNow() {
        int row = tblJobs.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a job first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String jobName = (String) mdlJobs.getValueAt(row, 0);

        int ok = JOptionPane.showConfirmDialog(this,
            "Run job NOW: " + jobName + "?\n\n" +
            "This will execute the job immediately.",
            "Confirm Run Now", JOptionPane.YES_NO_OPTION,
            JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;

        String sql =
            "BEGIN\n" +
            "    DBMS_SCHEDULER.RUN_JOB(:jobname, FALSE);\n" +
            "END;";
        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {
            cs.setString("jobname", jobName);
            cs.execute();
            con.commit();
            app.setStatus(jobName + " started successfully.",
                CrmAdminTool.CLR_SUCCESS);
            JOptionPane.showMessageDialog(this,
                jobName + " started.\n\n" +
                "Check Job Run History for result.",
                "Job Started", JOptionPane.INFORMATION_MESSAGE);
            refresh();
            loadJobHistory();
        } catch (SQLException ex) {
            app.setStatus("Run error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void removeJob() {
        int row = tblJobs.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a job first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String jobName = (String) mdlJobs.getValueAt(row, 0);

        int ok = JOptionPane.showConfirmDialog(this,
            "REMOVE job permanently: " + jobName + "?\n\n" +
            "This action cannot be undone.\n" +
            "The job will be dropped from the scheduler.",
            "Confirm Remove",
            JOptionPane.YES_NO_OPTION,
            JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;

        String sql =
            "BEGIN\n" +
            "    DBMS_SCHEDULER.DROP_JOB(:jobname, TRUE);\n" +
            "END;";
        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {
            cs.setString("jobname", jobName);
            cs.execute();
            con.commit();
            app.setStatus(jobName + " removed successfully.",
                CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Remove error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void changeSchedule() {
        int row = tblJobs.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a job first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String jobName     = (String) mdlJobs.getValueAt(row, 0);
        String currentSched= (String) mdlJobs.getValueAt(row, 3);

        String newSched = JOptionPane.showInputDialog(this,
            "Change schedule for: " + jobName + "\n\n" +
            "Current: " + currentSched + "\n\n" +
            "New repeat interval:\n" +
            "Examples:\n" +
            "  FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0\n" +
            "  FREQ=MINUTELY;INTERVAL=30\n" +
            "  FREQ=HOURLY;INTERVAL=1",
            "Change Schedule",
            JOptionPane.QUESTION_MESSAGE);

        if (newSched == null || newSched.trim().isEmpty()) return;

        String sql =
            "BEGIN\n" +
            "    DBMS_SCHEDULER.SET_ATTRIBUTE(\n" +
            "        name     => :jobname,\n" +
            "        attribute=> 'repeat_interval',\n" +
            "        value    => :interval);\n" +
            "END;";
        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {
            cs.setString("jobname",  jobName);
            cs.setString("interval", newSched.trim());
            cs.execute();
            con.commit();
            app.setStatus(jobName + " schedule updated.",
                CrmAdminTool.CLR_SUCCESS);
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Schedule change error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void addJob() {
        String jobName   = tfJobName.getText().trim().toUpperCase();
        String jobType   = (String) cbJobType.getSelectedItem();
        String jobAction = tfJobAction.getText().trim();
        String interval  = tfInterval.getText().trim();

        if (jobName.isEmpty() || jobAction.isEmpty()
                || interval.isEmpty()) {
            app.setStatus(
                "Job Name, Job Action and Interval are required.",
                CrmAdminTool.CLR_ERROR);
            return;
        }

        int ok = JOptionPane.showConfirmDialog(this,
            "Create new scheduler job?\n\n" +
            "  Name    : " + jobName   + "\n" +
            "  Type    : " + jobType   + "\n" +
            "  Action  : " + jobAction + "\n" +
            "  Schedule: " + interval,
            "Confirm Add Job",
            JOptionPane.YES_NO_OPTION);
        if (ok != JOptionPane.YES_OPTION) return;

        String sql = app.sql("query.scheduler.add");
        if (sql == null) return;

        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {
            cs.setString("jobname",   jobName);
            cs.setString("jobtype",   jobType);
            cs.setString("jobaction", jobAction);
            cs.setString("interval",  interval);
            cs.execute();
            con.commit();
            app.setStatus(jobName + " created successfully.",
                CrmAdminTool.CLR_SUCCESS);
            JOptionPane.showMessageDialog(this,
                "Job " + jobName + " created and enabled.",
                "Job Created",
                JOptionPane.INFORMATION_MESSAGE);
            clearForm();
            refresh();
        } catch (SQLException ex) {
            app.setStatus("Create error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void loadJobHistory() {
        int row = tblJobs.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a job first.", CrmAdminTool.CLR_WARN);
            return;
        }
        String jobName = (String) mdlJobs.getValueAt(row, 0);
        String q = app.sql("query.scheduler.history");
        if (q == null) return;

        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q)) {
            ps.setString(1, jobName);
            ResultSet rs = ps.executeQuery();
            mdlHistory.setRowCount(0);
            while (rs.next()) {
                mdlHistory.addRow(new Object[]{
                    rs.getString(1), rs.getString(2),
                    rs.getString(3), rs.getString(4),
                    rs.getString(5), rs.getString(6),
                    rs.getString(7)
                });
            }
            app.setStatus("History loaded for " + jobName +
                ": " + mdlHistory.getRowCount() + " run(s)",
                CrmAdminTool.CLR_SUCCESS);
        } catch (SQLException ex) {
            app.setStatus("History error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void clearForm() {
        tfJobName  .setText("");
        tfJobAction.setText("");
        cbJobType  .setSelectedIndex(0);
        cbFreq     .setSelectedIndex(0);
        tfInterval .setText(
            "FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0");
        tfInterval.setEnabled(false);
    }

    // =========================================================================
    //  RENDERERS
    // =========================================================================
    class StateRenderer extends DefaultTableCellRenderer {
        public Component getTableCellRendererComponent(
                JTable t, Object v, boolean sel,
                boolean foc, int r, int c) {
            super.getTableCellRendererComponent(
                t, v, sel, foc, r, c);
            setFont(new Font("Arial", Font.BOLD, 13));
            String val = v == null ? "" : v.toString();
            if      (val.equals("RUNNING"))
                setForeground(CrmAdminTool.CLR_INFO);
            else if (val.equals("SCHEDULED"))
                setForeground(CrmAdminTool.CLR_SUCCESS);
            else if (val.equals("DISABLED"))
                setForeground(CrmAdminTool.CLR_ERROR);
            else if (val.equals("FAILED"))
                setForeground(CrmAdminTool.CLR_ERROR);
            else
                setForeground(CrmAdminTool.CLR_TEXT);
            setBackground(sel ? CrmAdminTool.CLR_SEL
                : (r % 2 == 0 ? Color.WHITE : CrmAdminTool.CLR_ROW_ALT));
            setBorder(new EmptyBorder(0, 6, 0, 6));
            return this;
        }
    }

    class RunStatusRenderer extends DefaultTableCellRenderer {
        public Component getTableCellRendererComponent(
                JTable t, Object v, boolean sel,
                boolean foc, int r, int c) {
            super.getTableCellRendererComponent(
                t, v, sel, foc, r, c);
            setFont(new Font("Arial", Font.BOLD, 13));
            String val = v == null ? "" : v.toString();
            if      (val.equals("SUCCEEDED"))
                setForeground(CrmAdminTool.CLR_SUCCESS);
            else if (val.equals("FAILED"))
                setForeground(CrmAdminTool.CLR_ERROR);
            else if (val.equals("RUNNING"))
                setForeground(CrmAdminTool.CLR_INFO);
            else
                setForeground(CrmAdminTool.CLR_TEXT);
            setBackground(sel ? CrmAdminTool.CLR_SEL
                : (r % 2 == 0 ? Color.WHITE : CrmAdminTool.CLR_ROW_ALT));
            setBorder(new EmptyBorder(0, 6, 0, 6));
            return this;
        }
    }
}

// =============================================================================
//  LOGGER
// =============================================================================
class CrmLogger {

    private static final int    MAX_ENTRIES = 500;
    private static final String LOG_FILE    = "crm-admin.log";

    // In-memory log entries -- [timestamp, level, message]
    private final java.util.List<String[]> entries =
        new java.util.ArrayList<String[]>();

    private final SimpleDateFormat sdf =
        new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

    // -- Log a message --------------------------------------------------------
    synchronized void log(String level, String message) {
        String ts  = sdf.format(new Date());
        String[] entry = new String[]{ ts, level, message };

        // Keep max 500 entries in memory
        entries.add(entry);
        if (entries.size() > MAX_ENTRIES)
            entries.remove(0);

        // Write to log file
        writeToFile(ts, level, message);
    }

    // -- Convenience methods --------------------------------------------------
    void info   (String msg) { log("INFO",    msg); }
    void success(String msg) { log("SUCCESS", msg); }
    void warn   (String msg) { log("WARN",    msg); }
    void error  (String msg) { log("ERROR",   msg); }

    // -- Log exception with full stack trace ----------------------------------
    void error(String msg, Exception ex) {
        StringBuilder sb = new StringBuilder(msg);
        sb.append(" | Exception: ").append(ex.getMessage());
        // Add first 3 stack trace lines
        StackTraceElement[] stack = ex.getStackTrace();
        int limit = Math.min(3, stack.length);
        for (int i = 0; i < limit; i++) {
            sb.append(" | at ").append(stack[i].toString());
        }
        log("ERROR", sb.toString());
    }

    // -- Get all entries for display ------------------------------------------
    synchronized java.util.List<String[]> getEntries() {
        return new java.util.ArrayList<String[]>(entries);
    }

    // -- Clear in-memory entries ----------------------------------------------
    synchronized void clear() {
        entries.clear();
        log("INFO", "Log cleared by user");
    }

    // -- Export to file -------------------------------------------------------
    void exportTo(java.io.File file) throws IOException {
        java.util.List<String[]> copy = getEntries();
        try (PrintWriter pw = new PrintWriter(
                new FileWriter(file))) {
            pw.println("CRM Integration Admin Tool -- Log Export");
            pw.println("Generated: " + sdf.format(new Date()));
            pw.println(repeatStr("=", 80));
            for (String[] e : copy) {
                pw.printf("%-20s | %-8s | %s%n",
                    e[0], e[1], e[2]);
            }
            pw.println(repeatStr("=", 80));
            pw.println("Total entries: " + copy.size());
        }
    }

    // -- Java 8 compatible repeat helper -------------------------------------
    private String repeatStr(String s, int count) {
        StringBuilder sb = new StringBuilder(count * s.length());
        for (int i = 0; i < count; i++) sb.append(s);
        return sb.toString();
    }

    // -- Write single line to log file ----------------------------------------
    private void writeToFile(String ts, String level, String message) {
        try (PrintWriter pw = new PrintWriter(
                new FileWriter(LOG_FILE, true))) {
            pw.printf("%-20s | %-8s | %s%n", ts, level, message);
        } catch (IOException ignored) {
            // If file write fails -- silently ignore
            // App should not crash because of logging failure
        }
    }
}

// =============================================================================
//  TAB 9: HEALTH CHECK
// =============================================================================
class HealthCheckTab extends JPanel {

    private CrmAdminTool      app;
    private JComboBox         cbCredCode;
    private JTable            tblResults;
    private DefaultTableModel mdlResults;
    private JTextArea         taDetail;
    private JTable            tblUrls;
    private DefaultTableModel mdlUrls;
    private JTextField        tfUrlName, tfUrl;

    HealthCheckTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        add(buildTopBar(),    BorderLayout.NORTH);
        add(buildCenter(),    BorderLayout.CENTER);
        add(buildUrlPanel(),  BorderLayout.SOUTH);
    }

    // -- Top bar: cred selector + test button ---------------------------------
    private JPanel buildTopBar() {
        JPanel p = new JPanel(new FlowLayout(FlowLayout.LEFT, 12, 10));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new CompoundBorder(
            new MatteBorder(0, 0, 1, 0, CrmAdminTool.CLR_BORDER),
            new EmptyBorder(4, 8, 4, 8)));

        cbCredCode = new JComboBox();
        cbCredCode.setFont(CrmAdminTool.FONT_LABEL);
        cbCredCode.setBackground(Color.WHITE);
        cbCredCode.setPreferredSize(new Dimension(200, 30));

        JButton btnTestToken = CrmAdminTool.mkBtn(
            "Test APIC Token", CrmAdminTool.BTN_BLUE);
        JButton btnTestAll   = CrmAdminTool.mkBtn(
            "Test All Creds",  CrmAdminTool.BTN_GREEN);
        JButton btnClearLog  = CrmAdminTool.mkBtn(
            "Clear Results",   CrmAdminTool.BTN_GREY);

        btnTestToken.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                testApicToken((String) cbCredCode.getSelectedItem());
            }
        });
        btnTestAll.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { testAllCreds(); }
        });
        btnClearLog.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                mdlResults.setRowCount(0);
                taDetail.setText("");
            }
        });

        p.add(CrmAdminTool.mkLabel("Cred Code:"));
        p.add(cbCredCode);
        p.add(btnTestToken);
        p.add(btnTestAll);
        p.add(btnClearLog);

        JLabel hint = new JLabel(
            "  Tests GET_BEARER_TOKEN via Oracle package");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        p.add(hint);

        return p;
    }

    // -- Center: results table + detail panel ---------------------------------
    private JSplitPane buildCenter() {
        // Results table
        JPanel tablePanel = CrmAdminTool.mkPanel(new BorderLayout(0, 6));
        tablePanel.setBorder(new EmptyBorder(10, 10, 5, 10));

        JLabel lbl = new JLabel("Test Results");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        tablePanel.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Cred Code", "Status", "Response Time",
            "Token Length", "Tested At", "Detail"
        };
        mdlResults = CrmAdminTool.mkModel(cols);
        tblResults = CrmAdminTool.mkTable(mdlResults);
        tblResults.getColumnModel().getColumn(1)
            .setCellRenderer(new HealthStatusRenderer());

        int[] w = {130, 80, 110, 100, 130, 300};
        for (int i = 0; i < w.length; i++)
            tblResults.getColumnModel().getColumn(i)
                .setPreferredWidth(w[i]);

        tblResults.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                int row = tblResults.getSelectedRow();
                if (row >= 0) {
                    String detail = (String) mdlResults
                        .getValueAt(row, 5);
                    taDetail.setText(detail == null ? "" : detail);
                }
            }
        });

        tablePanel.add(CrmAdminTool.mkScroll(tblResults),
            BorderLayout.CENTER);

        // Detail panel
        JPanel detailPanel = CrmAdminTool.mkPanel(
            new BorderLayout(0, 6));
        detailPanel.setBorder(new EmptyBorder(5, 10, 5, 10));

        JLabel lblDetail = new JLabel("Last Result Detail");
        lblDetail.setFont(CrmAdminTool.FONT_HEADER);
        lblDetail.setForeground(CrmAdminTool.CLR_HDR_BG);
        detailPanel.add(lblDetail, BorderLayout.NORTH);

        taDetail = new JTextArea();
        taDetail.setEditable(false);
        taDetail.setFont(new Font("Courier New", Font.PLAIN, 12));
        taDetail.setForeground(CrmAdminTool.CLR_TEXT);
        taDetail.setBackground(new Color(245, 248, 252));
        taDetail.setLineWrap(true);
        taDetail.setWrapStyleWord(true);

        JScrollPane spDetail = new JScrollPane(taDetail);
        spDetail.setBorder(new LineBorder(CrmAdminTool.CLR_BORDER, 1));
        spDetail.setPreferredSize(new Dimension(0, 120));
        detailPanel.add(spDetail, BorderLayout.CENTER);

        JSplitPane sp = new JSplitPane(
            JSplitPane.VERTICAL_SPLIT,
            tablePanel, detailPanel);
        sp.setDividerLocation(300);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        return sp;
    }

    // -- Bottom: future health check URLs -------------------------------------
    private JPanel buildUrlPanel() {
        JPanel p = CrmAdminTool.mkPanel(new BorderLayout(0, 6));
        p.setBorder(new CompoundBorder(
            new MatteBorder(1, 0, 0, 0, CrmAdminTool.CLR_BORDER),
            new EmptyBorder(8, 10, 8, 10)));

        JLabel lbl = new JLabel(
            "Health Check URLs (Future -- CRM and other endpoints)");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        p.add(lbl, BorderLayout.NORTH);

        // URL table
        String[] cols = {"Name", "URL", "Last Status", "Last Tested"};
        mdlUrls = CrmAdminTool.mkModel(cols);
        tblUrls = CrmAdminTool.mkTable(mdlUrls);
        tblUrls.getColumnModel().getColumn(0).setPreferredWidth(120);
        tblUrls.getColumnModel().getColumn(1).setPreferredWidth(400);
        tblUrls.getColumnModel().getColumn(2).setPreferredWidth(80);
        tblUrls.getColumnModel().getColumn(3).setPreferredWidth(130);

        JScrollPane sp = CrmAdminTool.mkScroll(tblUrls);
        sp.setPreferredSize(new Dimension(0, 100));
        p.add(sp, BorderLayout.CENTER);

        // Add URL form
        JPanel addPanel = new JPanel(
            new FlowLayout(FlowLayout.LEFT, 8, 6));
        addPanel.setBackground(CrmAdminTool.CLR_BG);

        tfUrlName = CrmAdminTool.mkField(130);
        tfUrlName.setToolTipText("e.g. CRM Health Check");
        tfUrl     = CrmAdminTool.mkField(380);
        tfUrl.setToolTipText("e.g. https://crm.adib.ae/api/health");

        JButton btnAdd    = CrmAdminTool.mkBtn("Add URL",    CrmAdminTool.BTN_BLUE);
        JButton btnTest   = CrmAdminTool.mkBtn("Test URL",   CrmAdminTool.BTN_GREEN);
        JButton btnRemove = CrmAdminTool.mkBtn("Remove",     CrmAdminTool.BTN_RED);

        btnAdd.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { addUrl(); }
        });
        btnTest.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { testUrl(); }
        });
        btnRemove.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { removeUrl(); }
        });

        addPanel.add(CrmAdminTool.mkLabel("Name:"));
        addPanel.add(tfUrlName);
        addPanel.add(CrmAdminTool.mkLabel("URL:"));
        addPanel.add(tfUrl);
        addPanel.add(btnAdd);
        addPanel.add(btnTest);
        addPanel.add(btnRemove);

        p.add(addPanel, BorderLayout.SOUTH);
        return p;
    }

    // =========================================================================
    //  APIC TOKEN TEST
    // =========================================================================
    private void testApicToken(String credCode) {
        if (credCode == null || credCode.startsWith("--")) {
            app.setStatus("Select a Cred Code first.",
                CrmAdminTool.CLR_WARN);
            return;
        }

        app.setStatus("Testing APIC token for " + credCode + "...",
            CrmAdminTool.CLR_LABEL);

        // Use simple approach -- call function, measure time in Java
        String sql =
            "DECLARE\n" +
            "    v_token VARCHAR2(4000);\n" +
            "BEGIN\n" +
            "    v_token := PKG_CRM_INTEGRATION.GET_BEARER_TOKEN(?);\n" +
            "    ? := NVL(v_token, 'NULL');\n" +
            "END;";

        long startMs = System.currentTimeMillis();

        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {

            cs.setString(1, credCode);
            cs.registerOutParameter(2, Types.VARCHAR);
            cs.execute();

            long elapsedMs = System.currentTimeMillis() - startMs;
            String token   = cs.getString(2);
            String elapsed = String.format("%.2f",
                elapsedMs / 1000.0);

            String status, toklen, detail;

            if (token != null && !token.equals("NULL")
                    && token.length() > 10) {
                status  = "OK";
                toklen  = String.valueOf(token.length());
                detail  =
                    "Token obtained successfully\n" +
                    "Length  : " + token.length() + " chars\n" +
                    "Time    : " + elapsed + " sec\n" +
                    "Preview : Bearer " +
                    token.substring(0, Math.min(20, token.length()))
                    + "...";
            } else {
                status  = "FAILED";
                toklen  = "0";
                detail  = "Token returned NULL or empty\n" +
                          "Time: " + elapsed + " sec";
            }
            String testedAt = new SimpleDateFormat("HH:mm:ss")
                .format(new Date());

            mdlResults.insertRow(0, new Object[]{
                credCode, status,
                elapsed + " sec",
                toklen + " chars",
                testedAt,
                detail
            });

            taDetail.setText(detail);

            CrmAdminTool.LOGGER.log(
                "OK".equals(status) ? "SUCCESS" : "ERROR",
                "APIC TOKEN TEST [" + credCode + "] " +
                status + " " + elapsed + "sec len=" + toklen);

            if ("OK".equals(status)) {
                app.setStatus(
                    credCode + " -- APIC token OK (" +
                    elapsed + " sec, " + toklen + " chars)",
                    CrmAdminTool.CLR_SUCCESS);
            } else {
                app.setStatus(
                    credCode + " -- APIC token FAILED: " + detail,
                    CrmAdminTool.CLR_ERROR);
            }

        } catch (SQLException ex) {
            long elapsedMs = System.currentTimeMillis() - startMs;
            String elapsed = String.format("%.2f", elapsedMs / 1000.0);
            String testedAt = new SimpleDateFormat("HH:mm:ss")
                .format(new Date());
            String errMsg = "DB Error: " + ex.getMessage();
            mdlResults.insertRow(0, new Object[]{
                credCode, "ERROR",
                elapsed + " sec", "--",
                testedAt, errMsg
            });
            taDetail.setText(errMsg);
            CrmAdminTool.LOGGER.error(
                "APIC TOKEN TEST FAILED [" + credCode + "]", ex);
            app.setStatus("APIC test error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void testAllCreds() {
        int count = cbCredCode.getItemCount();
        int tested = 0;
        for (int i = 0; i < count; i++) {
            String cred = (String) cbCredCode.getItemAt(i);
            if (cred != null && !cred.startsWith("--")) {
                testApicToken(cred);
                tested++;
            }
        }
        app.setStatus("Tested " + tested + " credential(s).",
            CrmAdminTool.CLR_SUCCESS);
    }

    // =========================================================================
    //  URL HEALTH CHECK
    // =========================================================================
    private void addUrl() {
        String name = tfUrlName.getText().trim();
        String url  = tfUrl.getText().trim();
        if (name.isEmpty() || url.isEmpty()) {
            app.setStatus("Enter both Name and URL.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        mdlUrls.addRow(new Object[]{name, url, "--", "--"});
        tfUrlName.setText("");
        tfUrl.setText("");
        app.setStatus("URL added: " + name, CrmAdminTool.CLR_SUCCESS);
    }

    private void testUrl() {
        int row = tblUrls.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a URL to test.", CrmAdminTool.CLR_WARN);
            return;
        }
        String name = (String) mdlUrls.getValueAt(row, 0);
        String url  = (String) mdlUrls.getValueAt(row, 1);

        app.setStatus("Testing " + name + "...", CrmAdminTool.CLR_LABEL);

        // Test via Oracle UTL_HTTP through a PL/SQL call
        String sql =
            "DECLARE\n" +
            "    v_req   UTL_HTTP.REQ;\n" +
            "    v_resp  UTL_HTTP.RESP;\n" +
            "    v_start NUMBER;\n" +
            "    v_end   NUMBER;\n" +
            "BEGIN\n" +
            "    v_start := DBMS_UTILITY.GET_TIME;\n" +
            "    v_req   := UTL_HTTP.BEGIN_REQUEST(?, 'GET');\n" +
            "    v_resp  := UTL_HTTP.GET_RESPONSE(v_req);\n" +
            "    v_end   := DBMS_UTILITY.GET_TIME;\n" +
            "    ? := TO_CHAR(v_resp.STATUS_CODE);\n" +
            "    ? := TO_CHAR((v_end-v_start)/100,'FM999990.00');\n" +
            "    UTL_HTTP.END_RESPONSE(v_resp);\n" +
            "EXCEPTION\n" +
            "    WHEN OTHERS THEN\n" +
            "        ? := 'ERROR: ' || SQLERRM;\n" +
            "        ? := '--';\n" +
            "END;";

        try (Connection con = app.getConnection();
             CallableStatement cs = con.prepareCall(sql)) {
            cs.setString(1, url);
            cs.registerOutParameter(2, Types.VARCHAR);
            cs.registerOutParameter(3, Types.VARCHAR);
            cs.registerOutParameter(4, Types.VARCHAR);
            cs.registerOutParameter(5, Types.VARCHAR);
            cs.execute();

            String status  = cs.getString(2);
            String elapsed = cs.getString(3);
            if (status == null) status  = cs.getString(4);
            if (elapsed == null) elapsed = cs.getString(5);
            String testedAt = new SimpleDateFormat("HH:mm:ss")
                .format(new Date());

            mdlUrls.setValueAt(status,  row, 2);
            mdlUrls.setValueAt(testedAt, row, 3);

            String detail =
                "URL    : " + url      + "\n" +
                "Status : " + status   + "\n" +
                "Time   : " + elapsed  + " sec\n" +
                "Tested : " + testedAt;
            taDetail.setText(detail);

            boolean ok = "200".equals(status) || "201".equals(status)
                || "204".equals(status);
            app.setStatus(name + " -- HTTP " + status +
                " (" + elapsed + " sec)",
                ok ? CrmAdminTool.CLR_SUCCESS : CrmAdminTool.CLR_WARN);

            CrmAdminTool.LOGGER.log(
                ok ? "SUCCESS" : "WARN",
                "URL TEST [" + name + "] HTTP " + status +
                " " + elapsed + "sec");

        } catch (SQLException ex) {
            mdlUrls.setValueAt("ERROR", row, 2);
            app.setStatus("URL test error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    private void removeUrl() {
        int row = tblUrls.getSelectedRow();
        if (row < 0) {
            app.setStatus("Select a URL to remove.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        String name = (String) mdlUrls.getValueAt(row, 0);
        int ok = JOptionPane.showConfirmDialog(this,
            "Remove URL: " + name + "?",
            "Confirm", JOptionPane.YES_NO_OPTION);
        if (ok == JOptionPane.YES_OPTION) {
            mdlUrls.removeRow(row);
            app.setStatus("URL removed: " + name,
                CrmAdminTool.CLR_SUCCESS);
        }
    }

    // =========================================================================
    //  REFRESH
    // =========================================================================
    void refresh() {
        // Load cred codes
        String q = app.sql("query.cred.codes");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            cbCredCode.removeAllItems();
            cbCredCode.addItem("-- Select Cred Code --");
            while (rs.next())
                cbCredCode.addItem(rs.getString(1));
        } catch (SQLException ex) {
            app.setStatus("Health check init error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }

    // =========================================================================
    //  RENDERER
    // =========================================================================
    class HealthStatusRenderer extends DefaultTableCellRenderer {
        public Component getTableCellRendererComponent(
                JTable t, Object v, boolean sel,
                boolean foc, int r, int c) {
            super.getTableCellRendererComponent(
                t, v, sel, foc, r, c);
            setFont(new Font("Arial", Font.BOLD, 13));
            String val = v == null ? "" : v.toString();
            if      (val.equals("OK"))     setForeground(CrmAdminTool.CLR_SUCCESS);
            else if (val.equals("FAILED")) setForeground(CrmAdminTool.CLR_ERROR);
            else if (val.equals("ERROR"))  setForeground(CrmAdminTool.CLR_ERROR);
            else                           setForeground(CrmAdminTool.CLR_LABEL);
            setBackground(sel ? CrmAdminTool.CLR_SEL
                : (r % 2 == 0 ? Color.WHITE : CrmAdminTool.CLR_ROW_ALT));
            setBorder(new EmptyBorder(0, 6, 0, 6));
            return this;
        }
    }
}

// =============================================================================
//  TAB 10: TEST PUSH
// =============================================================================
class TestPushTab extends JPanel {

    private CrmAdminTool      app;
    private JComboBox         cbService;
    private JTextField        tfKeyValue;
    private JTable            tblResults;
    private DefaultTableModel mdlResults;
    private JTextArea         taDetail;

    TestPushTab(CrmAdminTool app) {
        this.app = app;
        setBackground(CrmAdminTool.CLR_BG);
        setLayout(new BorderLayout(0, 0));
        build();
    }

    private void build() {
        add(buildTopBar(),   BorderLayout.NORTH);
        add(buildCenter(),   BorderLayout.CENTER);
    }

    // -- Top bar --------------------------------------------------------------
    private JPanel buildTopBar() {
        JPanel p = new JPanel(new FlowLayout(FlowLayout.LEFT, 12, 10));
        p.setBackground(CrmAdminTool.CLR_PANEL);
        p.setBorder(new CompoundBorder(
            new MatteBorder(0, 0, 1, 0, CrmAdminTool.CLR_BORDER),
            new EmptyBorder(4, 8, 4, 8)));

        cbService  = new JComboBox();
        cbService.setFont(CrmAdminTool.FONT_LABEL);
        cbService.setBackground(Color.WHITE);
        cbService.setPreferredSize(new Dimension(250, 30));

        tfKeyValue = CrmAdminTool.mkField(160);
        tfKeyValue.setToolTipText(
            "Enter the source key value e.g. BUILDING_ID");

        JButton btnPush    = CrmAdminTool.mkBtn(
            "Push to CRM",    CrmAdminTool.BTN_BLUE);
        JButton btnClear   = CrmAdminTool.mkBtn(
            "Clear Results",  CrmAdminTool.BTN_GREY);

        btnPush .addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { push(); }
        });
        btnClear.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                mdlResults.setRowCount(0);
                taDetail.setText("");
            }
        });

        // Enter key triggers push
        tfKeyValue.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) { push(); }
        });

        p.add(CrmAdminTool.mkLabel("Service:"));
        p.add(cbService);
        p.add(CrmAdminTool.mkLabel("Key Value:"));
        p.add(tfKeyValue);
        p.add(btnPush);
        p.add(btnClear);

        JLabel hint = new JLabel(
            "  Calls PKG_CRM_INTEGRATION.SEND_TO_APIC " +
            "for single record test push");
        hint.setFont(CrmAdminTool.FONT_ITALIC);
        hint.setForeground(CrmAdminTool.CLR_LABEL);
        p.add(hint);

        return p;
    }

    // -- Center: results + detail ---------------------------------------------
    private JSplitPane buildCenter() {
        // Results table
        JPanel tablePanel = CrmAdminTool.mkPanel(
            new BorderLayout(0, 6));
        tablePanel.setBorder(new EmptyBorder(10, 10, 5, 10));

        JLabel lbl = new JLabel("Push Results");
        lbl.setFont(CrmAdminTool.FONT_HEADER);
        lbl.setForeground(CrmAdminTool.CLR_HDR_BG);
        lbl.setBorder(new EmptyBorder(0, 0, 6, 0));
        tablePanel.add(lbl, BorderLayout.NORTH);

        String[] cols = {
            "Service Name", "Key Value", "Status",
            "Response Time", "Log ID", "Pushed At", "Detail"
        };
        mdlResults = CrmAdminTool.mkModel(cols);
        tblResults = CrmAdminTool.mkTable(mdlResults);
        tblResults.getColumnModel().getColumn(2)
            .setCellRenderer(new CrmAdminTool.StatusRenderer());

        int[] w = {180, 120, 100, 100, 80, 120, 300};
        for (int i = 0; i < w.length; i++)
            tblResults.getColumnModel().getColumn(i)
                .setPreferredWidth(w[i]);

        tblResults.addMouseListener(new MouseAdapter() {
            public void mouseClicked(MouseEvent e) {
                int row = tblResults.getSelectedRow();
                if (row >= 0) {
                    Object val = mdlResults.getValueAt(row, 6);
                    taDetail.setText(val == null ? "" : val.toString());
                }
            }
        });

        tablePanel.add(CrmAdminTool.mkScroll(tblResults),
            BorderLayout.CENTER);

        // Detail panel
        JPanel detailPanel = CrmAdminTool.mkPanel(
            new BorderLayout(0, 6));
        detailPanel.setBorder(new EmptyBorder(5, 10, 10, 10));

        JLabel lblDetail = new JLabel("Push Result Detail");
        lblDetail.setFont(CrmAdminTool.FONT_HEADER);
        lblDetail.setForeground(CrmAdminTool.CLR_HDR_BG);
        detailPanel.add(lblDetail, BorderLayout.NORTH);

        taDetail = new JTextArea();
        taDetail.setEditable(false);
        taDetail.setFont(new Font("Courier New", Font.PLAIN, 12));
        taDetail.setForeground(CrmAdminTool.CLR_TEXT);
        taDetail.setBackground(new Color(245, 248, 252));
        taDetail.setLineWrap(true);
        taDetail.setWrapStyleWord(true);

        JScrollPane spDetail = new JScrollPane(taDetail);
        spDetail.setBorder(new LineBorder(CrmAdminTool.CLR_BORDER, 1));
        spDetail.setPreferredSize(new Dimension(0, 140));
        detailPanel.add(spDetail, BorderLayout.CENTER);

        JSplitPane sp = new JSplitPane(
            JSplitPane.VERTICAL_SPLIT,
            tablePanel, detailPanel);
        sp.setDividerLocation(320);
        sp.setBorder(null);
        sp.setBackground(CrmAdminTool.CLR_BG);
        return sp;
    }

    // =========================================================================
    //  PUSH
    // =========================================================================
    private void push() {
        String svcName  = (String) cbService.getSelectedItem();
        String keyValue = tfKeyValue.getText().trim();

        if (svcName == null || svcName.startsWith("--")) {
            app.setStatus("Select a service first.",
                CrmAdminTool.CLR_WARN);
            return;
        }
        if (keyValue.isEmpty()) {
            app.setStatus("Enter a key value to push.",
                CrmAdminTool.CLR_WARN);
            return;
        }

        int ok = JOptionPane.showConfirmDialog(this,
            "Push record to CRM?\n\n" +
            "Service  : " + svcName  + "\n" +
            "Key Value: " + keyValue + "\n\n" +
            "This will send a LIVE push to CRM via APIC.\n" +
            "Use only for testing with valid test data.",
            "Confirm Test Push",
            JOptionPane.YES_NO_OPTION,
            JOptionPane.WARNING_MESSAGE);
        if (ok != JOptionPane.YES_OPTION) return;

        app.setStatus("Pushing " + svcName +
            " key=" + keyValue + "...",
            CrmAdminTool.CLR_LABEL);

        // Get REGISTRY_ID first then call SEND_TO_APIC
        String sqlGetReg =
            "SELECT REGISTRY_ID FROM CRM_MPM_API_REGISTRY " +
            "WHERE SERVICE_NAME = ?";

        String sqlDelete =
            "DELETE FROM CRM_MPM_CRM_INTEGRATION_LOG " +
            "WHERE REGISTRY_ID = ? " +
            "AND SOURCE_RECORD_ID = ? " +
            "AND ATTEMPT_NO = 1";

        String sql =
            "BEGIN\n" +
            "    PKG_CRM_INTEGRATION.SEND_TO_APIC(\n" +
            "        p_registry_id          => ?,\n" +
            "        p_key_value            => ?,\n" +
            "        p_transaction_group_id => NULL,\n" +
            "        p_attempt_no           => 1,\n" +
            "        p_log_id_out           => ?);\n" +
            "END;";

        long startMs = System.currentTimeMillis();

        try (Connection con = app.getConnection()) {

            // Step 1 -- get registry ID
            long regId;
            try (PreparedStatement ps =
                    con.prepareStatement(sqlGetReg)) {
                ps.setString(1, svcName);
                ResultSet rs = ps.executeQuery();
                if (!rs.next()) {
                    app.setStatus("Service not found: " + svcName,
                        CrmAdminTool.CLR_ERROR);
                    return;
                }
                regId = rs.getLong(1);
            }

            // Step 2 -- delete existing test log entry if any
            try (PreparedStatement ps =
                    con.prepareStatement(sqlDelete)) {
                ps.setLong(1, regId);
                ps.setString(2, keyValue);
                ps.executeUpdate();
                con.commit();
            }

            // Step 3 -- call SEND_TO_APIC
            try (CallableStatement cs = con.prepareCall(sql)) {
                cs.setLong(1, regId);
                cs.setString(2, keyValue);
                cs.registerOutParameter(3, Types.NUMERIC);
                cs.execute();
                con.commit();

                long   elapsed  = System.currentTimeMillis() - startMs;
                long   logId    = cs.getLong(3);
                String pushedAt = new SimpleDateFormat("HH:mm:ss")
                    .format(new Date());
                String elapsed2 = String.format("%.2f",
                    elapsed / 1000.0);

                // Check log for result
                String status = "SENT";
                String detail =
                    "Service    : " + svcName   + "\n" +
                    "Key Value  : " + keyValue  + "\n" +
                    "Registry ID: " + regId     + "\n" +
                    "Log ID     : " + logId     + "\n" +
                    "Time       : " + elapsed2  + " sec\n" +
                    "Pushed At  : " + pushedAt  + "\n\n" +
                    "Check Monitor tab for final status.\n" +
                    "Log ID: " + logId;

                if (logId > 0) status = "SENT";
                else           status = "ERROR";

                mdlResults.insertRow(0, new Object[]{
                    svcName, keyValue, status,
                    elapsed2 + " sec",
                    String.valueOf(logId),
                    pushedAt, detail
                });

                taDetail.setText(detail);

                CrmAdminTool.LOGGER.log(
                    logId > 0 ? "SUCCESS" : "ERROR",
                    "TEST PUSH [" + svcName + "] key=" +
                    keyValue + " logId=" + logId);

                if (logId > 0) {
                    app.setStatus(
                        svcName + " pushed -- LogID: " +
                        logId + " (" + elapsed2 + "s) " +
                        "-- Check Monitor for result",
                        CrmAdminTool.CLR_SUCCESS);
                    JOptionPane.showMessageDialog(this,
                        "Push submitted successfully!\n\n" +
                        "Service  : " + svcName  + "\n" +
                        "Key Value: " + keyValue + "\n" +
                        "Log ID   : " + logId    + "\n\n" +
                        "Check Monitor tab for final status\n" +
                        "(SUCCESS / VALIDATION_FAILED etc)",
                        "Push Submitted",
                        JOptionPane.INFORMATION_MESSAGE);
                } else {
                    app.setStatus(
                        svcName + " push returned log ID 0 -- check package",
                        CrmAdminTool.CLR_WARN);
                }
            }
        } catch (SQLException ex) {
            long elapsed = System.currentTimeMillis() - startMs;
            String elapsed2 = String.format("%.2f", elapsed / 1000.0);
            String pushedAt = new SimpleDateFormat("HH:mm:ss")
                .format(new Date());
            String errMsg = ex.getMessage();

            mdlResults.insertRow(0, new Object[]{
                svcName, keyValue, "ERROR",
                elapsed2 + " sec", "--",
                pushedAt, errMsg
            });
            taDetail.setText("Error: " + errMsg);
            CrmAdminTool.LOGGER.error(
                "TEST PUSH FAILED [" + svcName +
                "] key=" + keyValue, ex);
            app.setStatus("Push error: " + errMsg,
                CrmAdminTool.CLR_ERROR);
        }
    }

    // =========================================================================
    //  REFRESH
    // =========================================================================
    void refresh() {
        String q = app.sql("query.service.names");
        if (q == null) return;
        try (Connection con = app.getConnection();
             PreparedStatement ps = con.prepareStatement(q);
             ResultSet rs = ps.executeQuery()) {
            cbService.removeAllItems();
            cbService.addItem("-- Select Service --");
            while (rs.next())
                cbService.addItem(rs.getString(1));
        } catch (SQLException ex) {
            app.setStatus("Service load error: " + ex.getMessage(),
                CrmAdminTool.CLR_ERROR);
        }
    }
}
