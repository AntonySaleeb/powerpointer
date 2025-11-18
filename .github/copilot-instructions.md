# PresenterPro AI Coding Agent Instructions

## Project Overview
**PresenterPro** is a cross-platform presentation remote system: a Flutter mobile app that controls presentations on a computer via a Python WebSocket server. The app uses **BLoC pattern** for state management and communicates with the Python server over WebSocket on port 8080.

### Architecture Overview
```
Flutter App (Mobile)              Python Server (Desktop)
├── BLoC (State Management)       ├── WebSocket Server (8080)
├── Services (WebSocket Client)   ├── PyAutoGUI (Keyboard Control)
├── Models (State & Commands)     ├── Slide Capture Extension
└── Screens (UI)                  └── Laser Pointer System
```

## Critical Data Flows

### 1. **Command Flow: App → Server**
- User action in UI → Event dispatched to BLoC
- BLoC handler converts to `SlideCommand` via `slide_controller_service.dart`
- Command sent as JSON over WebSocket: `{"command": "next|previous|laser_pointer|...", "params": {...}}`
- Server receives and executes via PyAutoGUI keyboard automation

**Key Commands** (enum in `lib/models/slide_command.dart`):
- Navigation: `next`, `previous`, `firstSlide`, `lastSlide`
- Presentation control: `startPresentation`, `endPresentation`
- Pointer: `laserPointer` (toggle), `laser_pointer_move` (JSON message with x/y percent)
- Screen: `blackScreen`, `whiteScreen`, `presentationView`, `volumeUp`, `volumeDown`, `mute`

### 2. **State Flow: BLoC Architecture**
**File Structure**:
- `lib/bloc/slide_controller_bloc.dart` - Main business logic engine (450+ lines)
- `lib/bloc/slide_controller_event.dart` - Event definitions
- `lib/models/slide_controller_state.dart` - State model with connection status, timer, pointer position
- `lib/services/slide_controller_service.dart` - WebSocket client wrapper

**State Updates Pattern**:
```dart
emit(state.copyWith(
  connectionStatus: ConnectionStatus.connected,
  isPresenting: true,
));
```
State is immutable; always use `copyWith()` for updates.

### 3. **Connection Lifecycle**
- User enters server IP → `ConnectToServer` event dispatched
- Service attempts WebSocket connection to `ws://[IP]:8080`
- On success: `ConnectionStatus.connected` + saves IP to `SharedPreferences`
- On failure: `ConnectionStatus.error` + auto-reconnect if enabled (configurable delays)
- Connection history stored locally for quick reconnection

## Essential Patterns & Conventions

### BLoC Event Handlers Pattern
**Location**: `lib/bloc/slide_controller_bloc.dart`
```dart
Future<void> _onEventName(EventName event, Emitter<SlideControllerState> emit) async {
  // 1. Validate state preconditions
  if (state.connectionStatus != ConnectionStatus.connected) {
    emit(state.copyWith(errorMessage: 'Not connected'));
    return;
  }
  
  // 2. Send command to service (fire-and-forget or await)
  await _service.sendCommand(SlideCommand.xxx);
  
  // 3. Emit state changes
  emit(state.copyWith(/* updated fields */));
}
```
**Key Pattern**: Use `emit()` with `copyWith()` to maintain immutability. Service calls are non-blocking for UI responsiveness.

### Settings Persistence
**Service**: `lib/services/settings_service.dart` (Singleton + SharedPreferences)
- Initialized in `main.dart` before `runApp()`
- Loads/saves `AppSettings` model to local storage
- All settings persist across app restarts

**When Adding Settings**:
1. Add field to `lib/models/app_settings.dart`
2. Update `fromJson()`/`toJson()` serialization
3. Add loader/saver to `SettingsService`
4. Wire into BLoC with `LoadSettings`/`UpdateSettings` events

### WebSocket Message Format
**For custom messages** (e.g., laser pointer movement):
```dart
final message = {
  'command': 'laser_pointer_move',  // Command name
  'params': {                        // Command parameters
    'x_percent': 45.5,
    'y_percent': 60.0,
  },
  'timestamp': DateTime.now().millisecondsSinceEpoch,
};
await _service.sendMessage(message);  // Raw JSON send, not SlideCommand
```
**Note**: Commands use `sendCommand(SlideCommand)` which auto-converts to JSON. Custom messages use `sendMessage()`.

### Orientation & Theme Responsiveness
**In `main.dart`**: 
- Theme switches between light/dark based on `state.settings.isDarkMode`
- Orientation locks/unlocks based on `state.isPointerMode` (landscape for pointer, portrait for controls)
- UI Scale applied via `TextScaler` in `MediaQuery` builder
- All managed in BLoC via `ToggleTheme` and `TogglePointerMode` events

## Python Server Architecture

**Key File**: `python_server/slide_controller_server.py`

### Command Execution
- Server receives JSON commands and routes to execution methods
- Uses `pyautogui` with `PAUSE=0.0` for zero-latency keyboard automation
- Supports: arrow keys (navigation), F5 (start), Esc (end), Ctrl+L (laser pointer)
- **Laser Pointer**: Uses PowerPoint's built-in laser mode via Ctrl+L + mouse movement

### Building & Distribution
- **GUI Build**: `python_server/build_exe.py` → PyInstaller exe
- **Batch Helpers**: `install.bat` (dependencies), `start_server.bat` (launcher)
- Auto-detects local IP address for display

## Critical Developer Workflows

### Flutter Development
```bash
# Full setup
flutter pub get                    # Install dependencies
flutter analyze                    # Check code quality (required pre-commit)
flutter run                        # Run on connected device/emulator
flutter run -d chrome             # Run on web (if needed)
```

### Python Server Development
```bash
# From python_server/
pip install -r requirements.txt    # Install deps
python slide_controller_server.py  # Run server directly
python -m py_compile *.py          # Syntax check
```

### Testing Locally
1. Start Python server: `python_server/start_server.bat`
2. Note displayed IP address
3. Run Flutter app: `flutter run`
4. Enter IP in app, connect
5. Test swipe gestures and buttons

### Code Quality
- **Linter**: `flutter analyze` (uses `analysis_options.yaml`)
- **Format**: `dart format lib/` (check before PR)
- **BLoC Cleanup**: Always call `bloc.close()` to dispose timers and subscriptions

## Integration Points & External Deps

### Flutter Dependencies (pubspec.yaml)
- `flutter_bloc` + `equatable`: State management & equality
- `web_socket_channel`: WebSocket client 
- `shared_preferences`: Local storage for settings/history
- `dynamic_color`: Material Design 3 theming
- `permission_handler`: Runtime permissions for sensors
- `sensors_plus`: Gyroscope/accelerometer (future pointer feature)
- `mobile_scanner`: QR code support (future IP discovery)

### Python Dependencies (requirements.txt)
- `websockets`: Async WebSocket server
- `pyautogui`: Cross-platform keyboard automation
- `slide_capture_extension`: Custom module for slide capture hooks

## Common Patterns to Replicate

### Adding a New Presentation Control Feature
1. **Define command** in `lib/models/slide_command.dart`:
   ```dart
   enum SlideCommand { myNewCommand, /* ... */ }
   // Add case to extension getter
   case SlideCommand.myNewCommand: return 'my_new_command';
   ```
2. **Create BLoC event** in `lib/bloc/slide_controller_event.dart`:
   ```dart
   class MyNewCommandEvent extends SlideControllerEvent {
     const MyNewCommandEvent();
   }
   ```
3. **Add handler** in BLoC:
   ```dart
   on<MyNewCommandEvent>(_onMyNewCommand);
   // In handler: await _service.sendCommand(SlideCommand.myNewCommand);
   ```
4. **Implement server-side** in `slide_controller_server.py`:
   ```python
   def handle_my_new_command(self):
       # Use pyautogui to automate action
   ```
5. **Add UI button** in `lib/screens/slide_control_screen.dart` that dispatches event

### Troubleshooting Connection Issues
- **Can't connect**: Verify both devices on same WiFi, firewall allows port 8080
- **Commands delayed**: Check server logs for `logger.info()` messages
- **State inconsistent**: Ensure all mutations use `emit(state.copyWith(...))` in BLoC
- **Settings lost**: Verify `SettingsService.initialize()` called in `main()` before `runApp()`

## File Organization Summary
```
lib/
  ├── main.dart              ← App entry, BLoC setup, theme
  ├── bloc/                  ← Business logic (events → state mutations)
  ├── models/                ← State, commands, settings (immutable)
  ├── services/              ← WebSocket client, local storage
  ├── screens/               ← UI layouts (listen to BLoC state)
  └── themes/                ← Light/dark theme definitions
python_server/
  ├── slide_controller_server.py ← Main async server
  ├── slide_capture_extension.py ← Custom slide capture hooks
  └── requirements.txt       ← Python dependencies
```

---
**Last Updated**: November 2025 | Covers: Flutter BLoC pattern, WebSocket communication, settings persistence, Python automation
