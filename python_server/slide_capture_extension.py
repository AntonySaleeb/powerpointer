#!/usr/bin/env python3
"""
Slide Capture Extension for Slide Controller Server
Adds screenshot capture functionality for live slide mirroring.
"""

import io
import base64
import logging
from PIL import Image, ImageGrab, ImageChops
import asyncio
import json
import hashlib

logger = logging.getLogger(__name__)

class SlideCaptureExtension:
    def __init__(self):
        self.capture_enabled = False
        self.capture_quality = 75  # Higher quality for better clarity
        self.capture_scale = 0.65   # Slightly larger for better readability
        self.last_screenshot_time = 0
        self.screenshot_cache = None
        self.last_screenshot_hash = None  # For duplicate detection
        self.last_screenshot_data = None  # Store last screenshot data
        self.streaming_task = None  # Background streaming task
        self.streaming_active = False  # Streaming state
        
        logger.info("⚡ LIVE STREAMING Slide Capture Extension initialized")
    
    def enable_capture(self, enabled=True):
        """Enable or disable slide capture"""
        self.capture_enabled = enabled
        
        # Reset hash when capture mode changes
        if enabled:
            self.last_screenshot_hash = None  # Reset to detect first slide as changed
            logger.info("📸 Slide capture ENABLED - Hash reset for fresh start")
        else:
            logger.info("📸 Slide capture DISABLED")
            # Optionally reset hash when disabled
            self.last_screenshot_hash = None
    
    def set_capture_quality(self, quality):
        """Set JPEG compression quality (1-100, higher = better quality)"""
        self.capture_quality = max(1, min(100, quality))
        logger.info(f"🎚️ Capture quality set to {self.capture_quality}%")
    
    def set_capture_scale(self, scale):
        """Set image scaling factor (0.1-1.0, smaller = faster transfer)"""
        self.capture_scale = max(0.1, min(1.0, scale))
        logger.info(f"📏 Capture scale set to {self.capture_scale}x")
    
    def _calculate_image_hash(self, image_data):
        """Calculate MD5 hash of image data for duplicate detection"""
        return hashlib.md5(image_data).hexdigest()
    
    def _has_slide_changed(self, new_image_data):
        """Check if the slide has actually changed by comparing image hashes"""
        new_hash = self._calculate_image_hash(new_image_data)
        
        if self.last_screenshot_hash is None:
            # First screenshot, always consider it changed
            self.last_screenshot_hash = new_hash
            return True
        
        if new_hash != self.last_screenshot_hash:
            # Slide has changed (including animations)
            self.last_screenshot_hash = new_hash
            logger.info("🔄 SLIDE/ANIMATION CHANGE DETECTED - New content found")
            return True
        else:
            # Same slide content - but for animations, we might want to force capture
            logger.info("⏸️  NO VISUAL CHANGE - Same content detected, skipping broadcast")
            return False
    
    def force_capture(self):
        """Force a capture even if content appears unchanged (for subtle animations)"""
        # Reset hash to force next capture to be considered changed
        self.last_screenshot_hash = None
    
    async def capture_slide_screenshot(self, force=False):
        """Capture current screen and return as base64 encoded image"""
        if not self.capture_enabled:
            logger.debug("📸 Capture disabled - Slideshow not active")
            return None
        
        try:
            # Capture screenshot
            screenshot = ImageGrab.grab()
            
            # Scale down for faster transfer
            if self.capture_scale != 1.0:
                new_size = (
                    int(screenshot.width * self.capture_scale),
                    int(screenshot.height * self.capture_scale)
                )
                screenshot = screenshot.resize(new_size, Image.Resampling.LANCZOS)  # Better quality resize
            
            # HIGH QUALITY: Better JPEG with optimization
            buffer = io.BytesIO()
            screenshot.save(buffer, format='JPEG', quality=self.capture_quality, optimize=True)
            buffer.seek(0)
            
            # Get raw image data
            raw_image_data = buffer.getvalue()
            
            # When forced (live streaming), ALWAYS send - no hash check
            if force:
                # Update hash for reference
                new_hash = self._calculate_image_hash(raw_image_data)
                self.last_screenshot_hash = new_hash
                
                # Encode to base64
                image_base64 = base64.b64encode(raw_image_data).decode('utf-8')
                data_url = f"data:image/jpeg;base64,{image_base64}"
                
                return data_url
            
            # For non-forced captures, check if changed
            if not self._has_slide_changed(raw_image_data):
                return "UNCHANGED"
            
            # Encode to base64
            image_base64 = base64.b64encode(raw_image_data).decode('utf-8')
            data_url = f"data:image/jpeg;base64,{image_base64}"
            
            return data_url
            
        except Exception as e:
            logger.error(f"❌ Screenshot capture failed: {e}")
            return None
    
    async def create_slide_message(self, slide_number=None, force=False):
        """Create a slide update message with screenshot"""
        screenshot_data = await self.capture_slide_screenshot(force=force)
        
        # When forced, screenshot_data should never be UNCHANGED
        # But handle it just in case
        if not screenshot_data or screenshot_data == "UNCHANGED":
            if force:
                logger.warning("⚠️ Forced capture returned no data - retrying")
                return None
            logger.info("🚫 SKIPPING BROADCAST - No slide change detected")
            return None
        
        message = {
            'type': 'slide_update',
            'timestamp': asyncio.get_event_loop().time(),
            'slide_number': slide_number,
            'has_image': True
        }
        
        message['image_data'] = screenshot_data
        message['image_format'] = 'jpeg'
        message['image_scale'] = self.capture_scale
        message['image_quality'] = self.capture_quality
        
        return message
    
    async def broadcast_slide_update(self, websockets_clients, slide_number=None, force=False):
        """Broadcast slide update to all connected clients"""
        if not websockets_clients:
            logger.debug("📡 No clients connected - Skipping broadcast")
            return
        if not self.capture_enabled:
            logger.debug("📡 Capture disabled - No slideshow mirroring needed")
            return
        
        try:
            message = await self.create_slide_message(slide_number, force=force)
            
            # Skip broadcast if no change detected (unless forced)
            if message is None and not force:
                logger.info("⏸️  BROADCAST SKIPPED - Slide unchanged")
                return
            
            message_json = json.dumps(message)
            
            # Send to all connected clients
            disconnected_clients = set()
            for client in websockets_clients:
                try:
                    await client.send(message_json)
                except Exception as e:
                    logger.warning(f"📱 Failed to send slide update to client: {e}")
                    disconnected_clients.add(client)
            
            # Remove disconnected clients
            for client in disconnected_clients:
                websockets_clients.discard(client)
            
            logger.info(f"⚡ Broadcast to {len(websockets_clients)} clients (forced={force})")
            
        except Exception as e:
            logger.error(f"❌ Failed to broadcast slide update: {e}")
    
    async def start_live_streaming(self, websockets_clients):
        """Start continuous live streaming of slides as backup"""
        self.streaming_active = True
        logger.info("🎥 LIVE STREAMING STARTED - Background sync every 500ms")
        logger.info(f"📱 Connected clients: {len(websockets_clients)}")
        
        while self.streaming_active and self.capture_enabled:
            try:
                # Capture and broadcast with force (always send, no hash check)
                await self.broadcast_slide_update(websockets_clients, force=True)
                
                # Wait 500ms before next capture (backup sync - commands trigger instant captures)
                await asyncio.sleep(0.5)
                
            except Exception as e:
                logger.error(f"❌ Streaming error: {e}")
                await asyncio.sleep(1)  # Wait before retry
        
        logger.info("🛑 LIVE STREAMING STOPPED")
    
    def stop_live_streaming(self):
        """Stop continuous live streaming"""
        self.streaming_active = False

# Global instance for easy integration
slide_capture = SlideCaptureExtension()

# Integration functions for the main server
def init_slide_capture():
    """Initialize slide capture (call this in main server startup)"""
    slide_capture.enable_capture(True)
    slide_capture.set_capture_quality(70)  # Better quality for readable text
    slide_capture.set_capture_scale(0.6)   # 60% size for better visibility
    logger.info("⚡ HIGH-QUALITY Slide Capture Extension ready!")

async def on_slide_change(websockets_clients, slide_number):
    """Call this when slides change to broadcast updates"""
    await slide_capture.broadcast_slide_update(websockets_clients, slide_number)

async def on_keystroke(websockets_clients, slide_number):
    """Call this after any keystroke to capture animations and slide changes"""
    logger.info("⌨️  Keystroke detected - Capturing for animations/slide changes")
    await slide_capture.broadcast_slide_update(websockets_clients, slide_number)

async def on_keystroke_force(websockets_clients, slide_number):
    """IMMEDIATE capture after keystroke - don't wait for next streaming frame!"""
    try:
        # Small delay to let PowerPoint transition complete
        await asyncio.sleep(0.05)  # 50ms - just enough for slide to render
        
        # Force immediate capture and broadcast
        await slide_capture.broadcast_slide_update(websockets_clients, force=True)
        logger.info(f"⚡ INSTANT capture triggered for slide {slide_number}")
    except Exception as e:
        logger.error(f"❌ Error in immediate capture: {e}")

async def on_presentation_start(websockets_clients):
    """Call this when presentation starts"""
    logger.info("🎬 SLIDESHOW STARTED - Starting LIVE STREAMING")
    slide_capture.enable_capture(True)
    
    # Start continuous live streaming in background
    slide_capture.streaming_task = asyncio.create_task(
        slide_capture.start_live_streaming(websockets_clients)
    )
    
    logger.info("🎥 LIVE STREAMING ACTIVE - Phone will show real-time PC screen")

async def on_presentation_end(websockets_clients):
    """Call this when presentation ends"""
    logger.info("🛑 SLIDESHOW ENDED - Stopping live streaming")
    
    # Stop live streaming
    slide_capture.stop_live_streaming()
    if slide_capture.streaming_task:
        slide_capture.streaming_task.cancel()
        try:
            await slide_capture.streaming_task
        except asyncio.CancelledError:
            pass
    
    slide_capture.enable_capture(False)
    
    # Send end message
    end_message = {
        'type': 'presentation_end',
        'timestamp': asyncio.get_event_loop().time()
    }
    message_json = json.dumps(end_message)
    
    for client in list(websockets_clients):
        try:
            await client.send(message_json)
            logger.info("📱 Client notified: Slideshow ended")
        except:
            websockets_clients.discard(client)
