/// App-owned preferences; live audio-session policy application belongs to GH-95.
struct EngineSoundPreferences: Equatable {
    static let enabledKey = "drive.engineSound.enabled"
    static let lowersOtherAudioKey = "drive.engineSound.lowersOtherAudio"

    var isEnabled = false
    var lowersOtherAudio = true
}
