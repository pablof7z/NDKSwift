import Foundation

enum MenuItem {
    case action(String, icon: String? = nil, action: () async throws -> Void)
    case submenu(String, icon: String? = nil, items: [MenuItem])
    case separator
    case back
}

class NavigableMenu {
    private var currentIndex = 0
    private var menuStack: [(items: [MenuItem], index: Int)] = []
    private var isActive = false
    
    func show(items: [MenuItem], title: String) async throws {
        isActive = true
        currentIndex = 0
        menuStack = [(items: items, index: 0)]
        
        // Enable raw mode for terminal
        enableRawMode()
        defer { disableRawMode() }
        
        while isActive {
            render(title: title)
            
            if let key = readKey() {
                await handleKeypress(key)
            }
        }
    }
    
    private func render(title: String) {
        // Clear screen
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        
        // Header
        let titleBox = """
        ┌─\("─".repeated(title.count + 2))─┐
        │ \(title) │
        └─\("─".repeated(title.count + 2))─┘
        """
        print(titleBox)
        print()
        
        let items = getCurrentItems()
        
        // Menu items
        for (index, item) in items.enumerated() {
            let isSelected = index == currentIndex
            let prefix = isSelected ? "▶ " : "  "
            
            switch item {
            case .action(let label, let icon, _):
                let iconStr = icon.map { $0 + " " } ?? ""
                let line = "\(prefix)\(iconStr)\(label)"
                if isSelected {
                    print("\u{001B}[7m\(line)\u{001B}[0m") // Reverse video
                } else {
                    print(line)
                }
                
            case .submenu(let label, let icon, _):
                let iconStr = icon.map { $0 + " " } ?? ""
                let line = "\(prefix)\(iconStr)\(label) ›"
                if isSelected {
                    print("\u{001B}[7m\(line)\u{001B}[0m")
                } else {
                    print(line)
                }
                
            case .separator:
                print("  " + "─".repeated(40))
                
            case .back:
                let line = "\(prefix)‹ Back"
                if isSelected {
                    print("\u{001B}[7m\(line)\u{001B}[0m")
                } else {
                    print(line)
                }
            }
        }
        
        // Footer
        print("\n" + "─".repeated(50))
        print("↑↓/jk Navigate • Enter Select • ESC/q Back")
    }
    
    private func getCurrentItems() -> [MenuItem] {
        return menuStack.last?.items ?? []
    }
    
    private func handleKeypress(_ key: String) async {
        switch key {
        case "\u{1B}[A", "w", "k": // Up arrow, w, k
            moveUp()
        case "\u{1B}[B", "s", "j": // Down arrow, s, j
            moveDown()
        case "\r", " ": // Enter, Space
            await selectItem()
        case "\u{1B}", "q": // ESC, q
            if menuStack.count > 1 {
                goBack()
            } else {
                isActive = false
            }
        case "\u{03}": // Ctrl+C
            exit(0)
        default:
            break
        }
    }
    
    private func moveUp() {
        let items = getCurrentItems()
        var newIndex = currentIndex
        
        repeat {
            newIndex = (newIndex - 1 + items.count) % items.count
        } while !isSelectable(items[newIndex]) && newIndex != currentIndex
        
        currentIndex = newIndex
        menuStack[menuStack.count - 1].index = newIndex
    }
    
    private func moveDown() {
        let items = getCurrentItems()
        var newIndex = currentIndex
        
        repeat {
            newIndex = (newIndex + 1) % items.count
        } while !isSelectable(items[newIndex]) && newIndex != currentIndex
        
        currentIndex = newIndex
        menuStack[menuStack.count - 1].index = newIndex
    }
    
    private func isSelectable(_ item: MenuItem) -> Bool {
        switch item {
        case .separator:
            return false
        default:
            return true
        }
    }
    
    private func selectItem() async {
        let items = getCurrentItems()
        let selectedItem = items[currentIndex]
        
        switch selectedItem {
        case .action(_, _, let action):
            isActive = false
            clearScreen()
            do {
                try await action()
                print("\nPress any key to continue...")
                _ = readKey()
            } catch {
                print("Error: \(error)")
                print("\nPress any key to continue...")
                _ = readKey()
            }
            isActive = true
            
        case .submenu(_, _, let subitems):
            menuStack.append((items: subitems + [.back], index: 0))
            currentIndex = 0
            
        case .back:
            goBack()
            
        case .separator:
            break
        }
    }
    
    private func goBack() {
        if menuStack.count > 1 {
            menuStack.removeLast()
            let previous = menuStack[menuStack.count - 1]
            currentIndex = previous.index
        }
    }
}

// Terminal utilities
func enableRawMode() {
    var raw = termios()
    tcgetattr(STDIN_FILENO, &raw)
    raw.c_lflag &= ~(UInt(ECHO | ICANON))
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
}

func disableRawMode() {
    var raw = termios()
    tcgetattr(STDIN_FILENO, &raw)
    raw.c_lflag |= UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
}

func readKey() -> String? {
    var buffer = [UInt8](repeating: 0, count: 4)
    let count = read(STDIN_FILENO, &buffer, 4)
    
    if count > 0 {
        return String(bytes: buffer[0..<count], encoding: .utf8)
    }
    return nil
}

func clearScreen() {
    print("\u{001B}[2J\u{001B}[H", terminator: "")
}

// Table rendering
struct TableRenderer {
    static func render(headers: [String], rows: [[String]], columnWidths: [Int]? = nil) {
        let widths = columnWidths ?? calculateColumnWidths(headers: headers, rows: rows)
        
        // Header
        let headerLine = headers.enumerated().map { index, header in
            header.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }.joined(separator: "│")
        print(headerLine)
        
        // Separator
        let separator = widths.map { "─".repeated($0) }.joined(separator: "┼")
        print(separator)
        
        // Rows
        for row in rows {
            let rowLine = row.enumerated().map { index, cell in
                cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "│")
            print(rowLine)
        }
    }
    
    private static func calculateColumnWidths(headers: [String], rows: [[String]]) -> [Int] {
        var widths = headers.map { $0.count + 2 }
        
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count + 2)
            }
        }
        
        return widths
    }
}

// String extension for repeating
extension String {
    func repeated(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}