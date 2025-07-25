import Foundation

struct Terminal {
    static func clear() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }
    
    static func moveCursor(x: Int, y: Int) {
        print("\u{001B}[\(y);\(x)H", terminator: "")
    }
    
    static func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
    }
    
    static func showCursor() {
        print("\u{001B}[?25h", terminator: "")
    }
    
    static func setRawMode() {
        var rawMode = termios()
        tcgetattr(STDIN_FILENO, &rawMode)
        rawMode.c_lflag &= ~(UInt(ICANON | ECHO))
        tcsetattr(STDIN_FILENO, TCSANOW, &rawMode)
    }
    
    static func restoreMode() {
        var normalMode = termios()
        tcgetattr(STDIN_FILENO, &normalMode)
        normalMode.c_lflag |= UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &normalMode)
    }
    
    static func getTerminalSize() -> (width: Int, height: Int) {
        var winsize = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsize) == 0 {
            return (Int(winsize.ws_col), Int(winsize.ws_row))
        }
        return (80, 24)
    }
    
    enum Color: String {
        case reset = "\u{001B}[0m"
        case black = "\u{001B}[30m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        case gray = "\u{001B}[90m"
        case brightRed = "\u{001B}[91m"
        case brightGreen = "\u{001B}[92m"
        case brightYellow = "\u{001B}[93m"
        case brightBlue = "\u{001B}[94m"
        case brightMagenta = "\u{001B}[95m"
        case brightCyan = "\u{001B}[96m"
        case brightWhite = "\u{001B}[97m"
    }
    
    static func color(_ text: String, _ color: Color) -> String {
        return "\(color.rawValue)\(text)\(Color.reset.rawValue)"
    }
    
    static func bold(_ text: String) -> String {
        return "\u{001B}[1m\(text)\u{001B}[22m"
    }
    
    static func dim(_ text: String) -> String {
        return "\u{001B}[2m\(text)\u{001B}[22m"
    }
}