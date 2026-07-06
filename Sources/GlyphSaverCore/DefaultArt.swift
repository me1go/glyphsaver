/// Built-in logo in ANSI-Shadow-style block lettering — original art, Omarchy-inspired vibe.
public enum DefaultArt {
    public static let text = """
     ██████╗ ██╗     ██╗   ██╗██████╗ ██╗  ██╗
    ██╔════╝ ██║     ╚██╗ ██╔╝██╔══██╗██║  ██║
    ██║  ███╗██║      ╚████╔╝ ██████╔╝███████║
    ██║   ██║██║       ╚██╔╝  ██╔═══╝ ██╔══██║
    ╚██████╔╝███████╗   ██║   ██║     ██║  ██║
     ╚═════╝ ╚══════╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝

             ░▒▓ TERMINAL SCREENSAVER ▓▒░
    """

    public static var art: AsciiArt {
        AsciiArt(text: text)
    }
}
