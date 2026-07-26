extends Node
# Autoload singleton — register as "MusicPlayer", after Settings.
#
# One looping track for the whole game. An autoload rather than a node in each scene,
# so the music runs continuously from the studio logo through the menus and into a
# level instead of restarting on every scene change — a track that resets each time you
# back out of a level is worse than no track at all.
#
# It plays on the Music bus, so the volume slider in Settings already controls it and
# nothing here has to know about volume at all.
#
# KNOWN, HARMLESS: quitting prints
#     Resource still in use: res://assets/audio/music/street lights.mp3
# An autoload is torn down after Godot's resource-leak check runs, so the stream is
# always still attached at that moment. Clearing it in _exit_tree does not help — the
# check has already happened. It has no effect on the running game; ignore that one
# line when scanning a run for real errors.

const TRACK_PATH: String = "res://assets/audio/music/street lights.mp3"
## Long enough that the track arrives rather than starts, short enough not to feel like
## a fault.
const FADE_IN: float = 1.5
const FADE_OUT: float = 0.8

var _player: AudioStreamPlayer = null


func _ready() -> void:
	var stream: AudioStream = load(TRACK_PATH)
	if stream == null:
		push_warning("MusicPlayer: no track at '%s'" % TRACK_PATH)
		return

	# Belt and braces with the .import setting: a re-import can reset that flag, and a
	# background track that stops after four minutes is a confusing bug to chase.
	if stream is AudioStreamMP3:
		stream.loop = true

	_player = AudioStreamPlayer.new()
	_player.name = "Stream"
	_player.stream = stream
	_player.bus = Settings.BUS_MUSIC
	# Nothing in this game pauses the SceneTree, but if anything ever does, the music
	# should carry on rather than cut out mid-bar.
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)

	play()


## Starts the track, fading up from silence. Safe to call when already playing.
func play() -> void:
	if _player == null or _player.playing:
		return
	_player.volume_db = -60.0
	_player.play()
	var tween: Tween = create_tween()
	tween.tween_property(_player, "volume_db", 0.0, FADE_IN)


func stop() -> void:
	if _player == null or not _player.playing:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_player, "volume_db", -60.0, FADE_OUT)
	tween.tween_callback(_player.stop)


func is_playing() -> bool:
	return _player != null and _player.playing


## For a future options entry or a cutscene that wants silence.
func set_muted(muted: bool) -> void:
	if muted:
		stop()
	else:
		play()
