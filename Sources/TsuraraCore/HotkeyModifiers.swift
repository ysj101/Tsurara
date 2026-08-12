import Foundation

/// NSEvent.ModifierFlags / Carbon 修飾キーのビット変換。
/// AppKit / Carbon を import せずに済むよう、安定した ABI 定数をここで定義する
/// （テスト可能にするため TsuraraCore に置く）。
public enum HotkeyModifiers {
    // NSEvent.ModifierFlags の deviceIndependent ビット
    public static let nsShift = 1 << 17
    public static let nsControl = 1 << 18
    public static let nsOption = 1 << 19
    public static let nsCommand = 1 << 20

    // Carbon (Events.h) の修飾キービット
    public static let carbonCmd: UInt32 = 0x0100
    public static let carbonShift: UInt32 = 0x0200
    public static let carbonOption: UInt32 = 0x0800
    public static let carbonControl: UInt32 = 0x1000

    /// NSEvent.ModifierFlags の rawValue から Carbon 修飾キーへ変換する。
    /// RegisterEventHotKey が解釈しない capsLock / fn / numericPad などのビットは
    /// 無視する（矢印キーやテンキーの録音時に混入し、登録は成功するのに
    /// 一致しないホットキーが生まれるのを防ぐ）。
    public static func carbonModifiers(fromNSEventFlags rawValue: Int) -> UInt32 {
        var result: UInt32 = 0
        if rawValue & nsCommand != 0 { result |= carbonCmd }
        if rawValue & nsOption != 0 { result |= carbonOption }
        if rawValue & nsControl != 0 { result |= carbonControl }
        if rawValue & nsShift != 0 { result |= carbonShift }
        return result
    }

    /// keyCode の妥当性検証。Carbon の仮想キーコードは UInt16 範囲。
    public static func validatedKeyCode(_ keyCode: Int) -> UInt32? {
        guard (0...Int(UInt16.max)).contains(keyCode) else { return nil }
        return UInt32(keyCode)
    }
}
