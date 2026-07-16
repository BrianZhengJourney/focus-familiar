import Cocoa

/// Builds a native Edit menu whose actions stay on AppKit's responder chain.
/// WKWebView's focused editor handles these selectors, including Command-V.
func makeStandardEditMenu(language: String) -> NSMenu {
    let zh = language != "en"
    let menu = NSMenu(title: zh ? "编辑" : "Edit")

    func item(_ zhTitle: String, _ enTitle: String, action: Selector,
              key: String, modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let menuItem = NSMenuItem(title: zh ? zhTitle : enTitle,
                                  action: action,
                                  keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = nil
        return menuItem
    }

    menu.addItem(item("撤销", "Undo", action: Selector(("undo:")), key: "z"))
    menu.addItem(item("重做", "Redo", action: Selector(("redo:")), key: "z",
                      modifiers: [.command, .shift]))
    menu.addItem(.separator())
    menu.addItem(item("剪切", "Cut", action: #selector(NSText.cut(_:)), key: "x"))
    menu.addItem(item("复制", "Copy", action: #selector(NSText.copy(_:)), key: "c"))
    menu.addItem(item("粘贴", "Paste", action: #selector(NSText.paste(_:)), key: "v"))
    menu.addItem(.separator())
    menu.addItem(item("全选", "Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
    return menu
}
