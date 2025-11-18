import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/slide_controller_bloc.dart';
import '../bloc/slide_controller_event.dart';
import '../models/slide_controller_state.dart';

class TouchLaserPointer extends StatelessWidget {
  const TouchLaserPointer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SlideControllerBloc, SlideControllerState>(
      builder: (context, state) {
        final scale = state.settings.uiScale;
        
        return ElevatedButton.icon(
          onPressed: () {
            context.read<SlideControllerBloc>().add(TogglePointerMode());
          },
          icon: Icon(
            state.isPointerMode ? Icons.touch_app : Icons.touch_app_outlined,
            size: 16 * scale,
          ),
          label: Text(
            'Pointer',
            style: TextStyle(
              fontSize: 14 * scale,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: state.isPointerMode 
                ? Colors.red.shade700 
                : Colors.blue.shade700,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: 24 * scale,
              vertical: 12 * scale,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20 * scale),
            ),
          ),
        );
      },
    );
  }
}

