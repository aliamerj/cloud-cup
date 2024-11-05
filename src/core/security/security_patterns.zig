pub const sql_injection_patterns = [_][]const u8{
    // Basic SQL Injection Keywords
    "SELECT",
    "INSERT",
    "DELETE",
    "UPDATE",
    "DROP",
    "UNION",
    "OR 1=1",
    "--",
    ";",
    "xp_cmdshell",
    "EXEC",
    "sysobjects",
    "syscolumns",
    "ALTER",
    "CREATE",
    "TRUNCATE",
    "GRANT",
    "REVOKE",
    "BACKUP",
    "RESTORE",
    "LOAD_FILE",
    "INTO OUTFILE",
    "OUTFILE",

    // Information Schema & Metadata
    "INFORMATION_SCHEMA",
    "TABLES",
    "COLUMNS",
    "SCHEMATA",

    // Commands for Delaying Execution
    "DECLARE",
    "WAITFOR DELAY",
    "AND 1=1",
    "AND 1=2",

    // Pattern Matching & Conditional Clauses
    "LIKE ",
    "#",
    ";--",
    "-- ",
    "/*...*/",
    "' OR '",
    "' AND '",
    "' UNION '",
    "AND",
    "OR",

    // System-Specific Functions and Operations
    "DATABASE()",
    "USER()",
    "VERSION()",
    "CURRENT_USER()",
    "SESSION_USER()",
    "CURRENT_DATABASE()",
    "SUBSTRING()",
    "LEFT()",
    "RIGHT()",
    "ASCII()",

    // Encoded or Obscured Patterns
    "0x", // Hexadecimal Indicator
    "CHAR(", "CHAR", // Can indicate obfuscation in SQL injections
    "%27", "%20", // URL encoded single quote and space

    // Comments and Escape Sequences
    "--",  "#",
    ";--", "-- ",
    "# ",

    // Platform-Specific and Miscellaneous
    "SP_", "PG_", "MYSQL", "SLEEP", "BENCHMARK", // Stored procedures and specific DB operations
};

pub const xss_patterns = [_][]const u8{
    "<script>",
    "javascript:",
    "onload=",
    "onclick=",
    "onerror=",
    "alert(",
    "eval(",
    "document.cookie",
    "window.location",
    "src=",
    "iframe",
    "<img",
    "<video",
    "<audio",
    "<object",
    "<embed",
    "<style",
    "<body",
    "<link",
    "expression(",
    "vbscript:",
    "livescript:",
    "mocha:",
    "text/javascript",
    "base64,",
    "<svg",
    "xlink:href",
    "<meta",
    "<form",
    "innerHTML",
    "outerHTML",
    "setTimeout(",
    "setInterval(",
    "data:text/html",
    "data:image/svg+xml",
    "&#x3C;script&#x3E;",
    "&#x3C;img&#x3E;",
    "&#x3C;iframe&#x3E;",
};

pub const traversal_patterns = [_][]const u8{
    "../",         "..\\",                  "%2e%2e%2f", "%2e%2e%5c", "%252e%252e%255c", "%c0%ae%c0%ae", "%uff0e%uff0e%2f",
    "/etc/passwd", "C:\\Windows\\System32", "%00",       "....//",    "....\\\\",        "%2e%2e%5c%2f", "%2e%2e%2f%2e%2e%2f",
    "%c0%af",      "%c1%9c",                "%e0%80%af", "file:///",
};

const malicious_file_extensions = [_][]const u8{
    // Executable files
    ".exe",  ".msi",  ".bin",   ".com",   ".cpl",  ".dll",   ".scr",  ".sys",

    // Scripting and server-side code
    ".php",  ".jsp",  ".asp",   ".aspx",  ".cgi",  ".pl",    ".py",   ".rb",
    ".sh",   ".bat",  ".cmd",

    // Compiled and intermediate files
      ".class", ".jar",  ".war",   ".pyc",  ".pyo",

    // Shell scripts and batch files
    ".sh",   ".bash", ".zsh",   ".bat",   ".cmd",

    // Web files with potential code injection risks
     ".html",  ".htm",  ".xhtml",
    ".xml",  ".svg",  ".php3",  ".php4",  ".php5", ".phtml",

    // Archive files with executable contents
    ".zip",  ".rar",
    ".tar",  ".gz",   ".7z",    ".bz2",   ".iso",  ".dmg",

    // Dangerous images and videos with metadata injection risks
      ".svg",  ".svgz",
    ".webp",

    // Database files
    ".db",   ".dbf",   ".sql",

    // Files used for system manipulation
      ".ps1",  ".vbs",   ".reg",  ".lnk",
    ".inf",  ".ini",

    // MacOS/Linux specific executables
     ".dylib", ".o",     ".so",

    // Office files with macro vulnerabilities
      ".docm",  ".xlsm", ".pptm",
    ".xltm", ".dotm", ".potm",  ".ppam",  ".ppsm", ".sldm",

    // Unsafe audio and video with script execution capabilities
     ".midi", ".mid",
    ".mka",  ".m3u",  ".pls",
};

pub const suspicious_user_agents = [_][]const u8{
    "curl", // Command line tool for transferring data
    "wget", // Command line utility for retrieving files
    "Java", // Java-based bots
    "Python-urllib", // Python script bots
    "libwww-perl", // Perl library for web access
    "HTTrack", // Website copier
    "Nmap", // Network mapper tool
    "scan", // Generic term often used by scanners
    "DDoS", // DDoS attack scripts
    "Apache-HttpClient", // Apache HTTP client
    "Go-http-client", // Go's HTTP client
    "httpclient", // General HTTP clients
    "Bot", // Generic bot indicator
    "Crawler", // Generic crawler
    "Baidoobot", // Baidu web crawler
    "Bingbot", // Bing's web crawler
    "Googlebot", // Google's web crawler
    "Slurp", // Yahoo's web crawler
    "YandexBot", // Yandex's web crawler
    "AhrefsBot", // Ahrefs SEO tool bot
    "SemrushBot", // Semrush SEO tool bot
    "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)", // Old Internet Explorer, often used by bots
    "Mozilla/5.0 (compatible; Bot/1.0)", // Generic bot user-agent
};

pub const required_headers = [_][]const u8{
    "Host", // Required for HTTP/1.1
    "User-Agent", // Identify the client software
    "Accept", // Types of media that are acceptable for the response
};
