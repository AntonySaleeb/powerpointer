import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:slid_controller/models/app_settings.dart';
import '../models/slide_controller_state.dart';
import '../models/slide_command.dart';
import '../services/slide_controller_service.dart';
import '../services/settings_service.dart';
import 'slide_controller_event.dart';

class SlideControllerBloc extends Bloc<SlideControllerEvent, SlideControllerState> {
  final SlideControllerService _service = SlideControllerService();
  final SettingsService _settingsService = SettingsService();
  Timer? _timer;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<Map<String, dynamic>>? _slideMessageSubscription;

  SlideControllerBloc() : super(const SlideControllerState()) {
    on<ConnectToServer>(_onConnectToServer);
    on<DisconnectFromServer>(_onDisconnectFromServer);
    on<SendSlideCommand>(_onSendSlideCommand);
    on<NextSlide>(_onNextSlide);
    on<PreviousSlide>(_onPreviousSlide);
    on<StartPresentation>(_onStartPresentation);
    on<EndPresentation>(_onEndPresentation);
    
    // Advanced features
    on<ToggleLaserPointer>(_onToggleLaserPointer);
    on<SendLaserPointerMove>(_onSendLaserPointerMove);
    on<SendLaserPointerClick>(_onSendLaserPointerClick);
    
    // Gyroscope Pointer
    on<StartPointer>(_onStartPointer);
    on<StopPointer>(_onStopPointer);
    on<MovePointer>(_onMovePointer);
    on<TogglePointerMode>(_onTogglePointerMode);
    on<ToggleBlackScreen>(_onToggleBlackScreen);
    on<ToggleWhiteScreen>(_onToggleWhiteScreen);
    on<TogglePresentationView>(_onTogglePresentationView);
    on<VolumeUp>(_onVolumeUp);
    on<VolumeDown>(_onVolumeDown);
    on<ToggleMute>(_onToggleMute);
    on<GoToFirstSlide>(_onGoToFirstSlide);
    on<GoToLastSlide>(_onGoToLastSlide);
    on<StartTimer>(_onStartTimer);
    on<StopTimer>(_onStopTimer);
    on<ResetTimer>(_onResetTimer);
    on<UpdateTimer>(_onUpdateTimer);
    
    // Settings events
    on<LoadSettings>(_onLoadSettings);
    on<UpdateSettings>(_onUpdateSettings);
    on<ToggleTheme>(_onToggleTheme);
    on<AttemptReconnect>(_onAttemptReconnect);
    on<LoadConnectionHistory>(_onLoadConnectionHistory);
    
    // Slide image events
    on<UpdateSlideImage>(_onUpdateSlideImage);
    on<ClearSlideImage>(_onClearSlideImage);
    on<HandleConnectionError>(_onHandleConnectionError);
    
    // Initialize settings and connection monitoring
    _initializeBloc();
  }
  
  void _initializeBloc() {
    // Load initial settings
    add(LoadSettings());
    add(LoadConnectionHistory());
    
    // Monitor connection state
    _connectionSubscription = _service.connectionStateStream.listen((isConnected) {
      if (!isConnected && state.connectionStatus == ConnectionStatus.connected) {
        add(DisconnectFromServer());
        
        // Auto-reconnect if enabled
        if (state.settings.autoReconnect) {
          add(AttemptReconnect());
        }
      }
    });
    
    // Monitor errors
    _errorSubscription = _service.errorStream.listen((error) {
      add(HandleConnectionError(error));
    });
    
    // Monitor slide messages
    _slideMessageSubscription = _service.slideMessageStream.listen((message) {
      _handleSlideMessage(message);
    });
  }

  Future<void> _onConnectToServer(
    ConnectToServer event,
    Emitter<SlideControllerState> emit,
  ) async {
    emit(state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      serverIp: event.serverIp,
      errorMessage: null,
      reconnectAttempt: 0,
    ));

    try {
      final success = await _service.connect(event.serverIp);
      if (success) {
        // Save to connection history and settings
        await _settingsService.addToConnectionHistory(event.serverIp);
        await _settingsService.setLastUsedIp(event.serverIp);
        
        emit(state.copyWith(
          connectionStatus: ConnectionStatus.connected,
          errorMessage: null,
        ));
        
        // Auto-start timer if enabled
        if (state.settings.autoStartTimer) {
          add(StartTimer());
        }
      } else {
        emit(state.copyWith(
          connectionStatus: ConnectionStatus.error,
          errorMessage: 'Failed to connect to server',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage: 'Connection error: $e',
      ));
    }
  }

  Future<void> _onDisconnectFromServer(
    DisconnectFromServer event,
    Emitter<SlideControllerState> emit,
  ) async {
    _service.disconnect();
    emit(state.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
      isPresenting: false,
      currentSlide: 0,
    ));
  }

  Future<void> _onSendSlideCommand(
    SendSlideCommand event,
    Emitter<SlideControllerState> emit,
  ) async {
    if (state.connectionStatus != ConnectionStatus.connected) {
      emit(state.copyWith(
        errorMessage: 'Not connected to server',
      ));
      return;
    }

    final success = await _service.sendCommand(event.command);
    if (!success) {
      emit(state.copyWith(
        errorMessage: 'Failed to send command',
      ));
    }
  }

  Future<void> _onNextSlide(
    NextSlide event,
    Emitter<SlideControllerState> emit,
  ) async {
    // Fire-and-forget - don't wait for response
    _service.sendCommand(SlideCommand.next);
    emit(state.copyWith(currentSlide: state.currentSlide + 1));
  }

  Future<void> _onPreviousSlide(
    PreviousSlide event,
    Emitter<SlideControllerState> emit,
  ) async {
    if (state.currentSlide > 0) {
      // Fire-and-forget - don't wait for response
      _service.sendCommand(SlideCommand.previous);
      emit(state.copyWith(currentSlide: state.currentSlide - 1));
    }
  }

  Future<void> _onStartPresentation(
    StartPresentation event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.startPresentation),
      emit,
    );
    emit(state.copyWith(isPresenting: true, currentSlide: 1));
  }

  Future<void> _onEndPresentation(
    EndPresentation event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.endPresentation),
      emit,
    );
    emit(state.copyWith(isPresenting: false, currentSlide: 0));
  }

  void _handleSlideMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'slide_update':
        print('🖼️ Processing slide update for slide ${message['slide_number']}');
        add(UpdateSlideImage(
          message['image_data'],
          message['slide_number'],
        ));
        break;
      case 'presentation_end':
        print('🛑 Processing presentation end');
        add(ClearSlideImage());
        break;
    }
  }

  @override
  Future<void> close() {
    _service.dispose();
    _timer?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _slideMessageSubscription?.cancel();
    return super.close();
  }

  // Advanced feature handlers
  Future<void> _onToggleLaserPointer(
    ToggleLaserPointer event,
    Emitter<SlideControllerState> emit,
  ) async {
    // Only toggle if laser pointer is enabled in settings
    if (!state.settings.laserPointerEnabled) {
      emit(state.copyWith(
        errorMessage: 'Laser pointer is disabled in settings',
      ));
      return;
    }
    
    final newState = !state.isLaserPointerActive;
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.laserPointer),
      emit,
    );
    emit(state.copyWith(isLaserPointerActive: newState));
  }

  Future<void> _onSendLaserPointerMove(
    SendLaserPointerMove event,
    Emitter<SlideControllerState> emit,
  ) async {
    if (!state.settings.laserPointerEnabled || !state.isLaserPointerActive) {
      print('Laser pointer move rejected: enabled=${state.settings.laserPointerEnabled}, active=${state.isLaserPointerActive}');
      return;
    }

    try {
      if (state.connectionStatus == ConnectionStatus.connected) {
        final message = {
          'command': 'laser_pointer_move',
          'params': {
            'x_percent': event.xPercent,
            'y_percent': event.yPercent,
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        print('Sending laser pointer move: x=${event.xPercent}%, y=${event.yPercent}%');
        await _service.sendMessage(message);
      } else {
        print('Not connected - cannot send laser pointer move');
      }
    } catch (e) {
      print('Error sending laser pointer move: $e');
      emit(state.copyWith(errorMessage: 'Failed to move laser pointer: $e'));
    }
  }

  Future<void> _onSendLaserPointerClick(
    SendLaserPointerClick event,
    Emitter<SlideControllerState> emit,
  ) async {
    if (!state.settings.laserPointerEnabled || !state.isLaserPointerActive) {
      return;
    }

    try {
      if (state.connectionStatus == ConnectionStatus.connected) {
        final message = {
          'command': 'laser_pointer_click',
          'params': {
            'x_percent': event.xPercent,
            'y_percent': event.yPercent,
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        await _service.sendMessage(message);
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to click laser pointer: $e'));
    }
  }

  // Gyroscope Pointer Event Handlers
  Future<void> _onStartPointer(
    StartPointer event,
    Emitter<SlideControllerState> emit,
  ) async {
    if (!state.isPresenting) return; // Only work during presentations
    
    emit(state.copyWith(isGyroscopePointerActive: true));
  }

  Future<void> _onStopPointer(
    StopPointer event,
    Emitter<SlideControllerState> emit,
  ) async {
    emit(state.copyWith(isGyroscopePointerActive: false));
  }

  void _onMovePointer(
    MovePointer event,
    Emitter<SlideControllerState> emit,
  ) {
    // For touch-based pointer, we don't need gyroscope to be active
    if (!state.isPresenting) {
      return;
    }
    
    // Update local pointer position (non-blocking)
    emit(state.copyWith(pointerX: event.x, pointerY: event.y));
    
    // Send real-time pointer position to server (non-blocking)
    if (state.connectionStatus == ConnectionStatus.connected) {
      final message = {
        'command': 'laser_pointer_move',
        'params': {
          'x_percent': event.x,
          'y_percent': event.y,
        },
      };

      // Send message without waiting for response (non-blocking)
      _service.sendMessage(message);
    }
  }

  Future<void> _onToggleBlackScreen(
    ToggleBlackScreen event,
    Emitter<SlideControllerState> emit,
  ) async {
    final newState = !state.isBlackScreen;
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.blackScreen),
      emit,
    );
    emit(state.copyWith(
      isBlackScreen: newState,
      isWhiteScreen: newState ? false : state.isWhiteScreen,
    ));
  }

  Future<void> _onToggleWhiteScreen(
    ToggleWhiteScreen event,
    Emitter<SlideControllerState> emit,
  ) async {
    final newState = !state.isWhiteScreen;
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.whiteScreen),
      emit,
    );
    emit(state.copyWith(
      isWhiteScreen: newState,
      isBlackScreen: newState ? false : state.isBlackScreen,
    ));
  }

  Future<void> _onTogglePresentationView(
    TogglePresentationView event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.presentationView),
      emit,
    );
  }

  Future<void> _onVolumeUp(
    VolumeUp event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.volumeUp),
      emit,
    );
  }

  Future<void> _onVolumeDown(
    VolumeDown event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.volumeDown),
      emit,
    );
  }

  Future<void> _onToggleMute(
    ToggleMute event,
    Emitter<SlideControllerState> emit,
  ) async {
    final newState = !state.isMuted;
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.mute),
      emit,
    );
    emit(state.copyWith(isMuted: newState));
  }

  Future<void> _onGoToFirstSlide(
    GoToFirstSlide event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.firstSlide),
      emit,
    );
    emit(state.copyWith(currentSlide: 1));
  }

  Future<void> _onGoToLastSlide(
    GoToLastSlide event,
    Emitter<SlideControllerState> emit,
  ) async {
    await _onSendSlideCommand(
      const SendSlideCommand(SlideCommand.lastSlide),
      emit,
    );
  }

  Future<void> _onStartTimer(
    StartTimer event,
    Emitter<SlideControllerState> emit,
  ) async {
    _timer?.cancel();
    emit(state.copyWith(isTimerRunning: true));
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      add(UpdateTimer(state.presentationTimer + 1));
    });
  }

  Future<void> _onStopTimer(
    StopTimer event,
    Emitter<SlideControllerState> emit,
  ) async {
    _timer?.cancel();
    emit(state.copyWith(isTimerRunning: false));
  }

  Future<void> _onResetTimer(
    ResetTimer event,
    Emitter<SlideControllerState> emit,
  ) async {
    _timer?.cancel();
    emit(state.copyWith(
      presentationTimer: 0,
      isTimerRunning: false,
    ));
  }

  Future<void> _onUpdateTimer(
    UpdateTimer event,
    Emitter<SlideControllerState> emit,
  ) async {
    emit(state.copyWith(presentationTimer: event.seconds));
  }
  
  // Settings event handlers
  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SlideControllerState> emit,
  ) async {
    try {
      print('BLoC: Loading settings...');
      final settings = await _settingsService.loadSettings();
      print('BLoC: Settings loaded: isDarkMode=${settings.isDarkMode}, uiScale=${settings.uiScale}');
      emit(state.copyWith(settings: settings));
      print('BLoC: State updated with new settings');
    } catch (e) {
      print('BLoC: Error loading settings: $e');
      // Emit default settings on error
      emit(state.copyWith(settings: const AppSettings()));
    }
  }

  Future<void> _onUpdateSettings(
    UpdateSettings event,
    Emitter<SlideControllerState> emit,
  ) async {
    try {
      print('BLoC: Saving settings: isDarkMode=${event.settings.isDarkMode}, uiScale=${event.settings.uiScale}');
      
      // First update the state immediately for responsive UI
      emit(state.copyWith(settings: event.settings));
      print('BLoC: State updated immediately with new settings');
      
      // Then save to persistent storage
      final success = await _settingsService.saveSettings(event.settings);
      if (success) {
        print('BLoC: Settings saved successfully to persistent storage');
      } else {
        print('BLoC: Failed to save settings to persistent storage');
        // Optionally, you could revert the state here if save failed
      }
    } catch (e) {
      print('BLoC: Error updating settings: $e');
      // Could revert state or show error message
    }
  }

  Future<void> _onToggleTheme(
    ToggleTheme event,
    Emitter<SlideControllerState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      isDarkMode: !state.settings.isDarkMode,
    );
    print('BLoC: Toggling theme to: ${newSettings.isDarkMode ? "Dark" : "Light"}');
    add(UpdateSettings(newSettings));
  }
  
  Future<void> _onAttemptReconnect(
    AttemptReconnect event,
    Emitter<SlideControllerState> emit,
  ) async {
    if (state.serverIp == null) return;
    
    emit(state.copyWith(
      connectionStatus: ConnectionStatus.reconnecting,
      reconnectAttempt: state.reconnectAttempt + 1,
    ));
    
    // Start auto-reconnect with settings
    _service.startAutoReconnect(
      maxAttempts: state.settings.reconnectAttempts,
      delaySeconds: state.settings.reconnectDelaySeconds,
    );
  }
  
  Future<void> _onLoadConnectionHistory(
    LoadConnectionHistory event,
    Emitter<SlideControllerState> emit,
  ) async {
    try {
      final history = await _settingsService.getConnectionHistory();
      emit(state.copyWith(connectionHistory: history));
    } catch (e) {
      print('Error loading connection history: $e');
    }
  }
  
  // Slide image event handlers
  Future<void> _onUpdateSlideImage(
    UpdateSlideImage event,
    Emitter<SlideControllerState> emit,
  ) async {
    print('BLoC: Updating slide image for slide ${event.slideNumber}');
    emit(state.copyWith(
      currentSlideImageData: event.imageData,
      hasSlideImage: event.imageData != null,
      currentSlide: event.slideNumber ?? state.currentSlide,
      slideImageTimestamp: DateTime.now().millisecondsSinceEpoch, // Force rebuild
    ));
  }

  Future<void> _onClearSlideImage(
    ClearSlideImage event,
    Emitter<SlideControllerState> emit,
  ) async {
    print('BLoC: Clearing slide image');
    emit(state.copyWith(
      currentSlideImageData: null,
      hasSlideImage: false,
    ));
  }

  Future<void> _onHandleConnectionError(
    HandleConnectionError event,
    Emitter<SlideControllerState> emit,
  ) async {
    print('BLoC: Handling connection error: ${event.error}');
    emit(state.copyWith(
      connectionStatus: ConnectionStatus.error,
      errorMessage: event.error,
    ));
  }

  Future<void> _onTogglePointerMode(
    TogglePointerMode event,
    Emitter<SlideControllerState> emit,
  ) async {
    print('BLoC: Toggling pointer mode to ${!state.isPointerMode}');
    emit(state.copyWith(isPointerMode: !state.isPointerMode));
    
    // Send laser pointer toggle command to server
    if (!state.isPointerMode) {
      // Turning pointer mode ON - enable laser pointer
      print('BLoC: Enabling laser pointer on server');
      await _service.sendCommand(SlideCommand.laserPointer);
    } else {
      // Turning pointer mode OFF - disable laser pointer
      print('BLoC: Disabling laser pointer on server');
      await _service.sendCommand(SlideCommand.laserPointer);
    }
  }
}
