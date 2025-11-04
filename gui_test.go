package vz_test

import (
	"testing"

	"github.com/Code-Hex/vz/v3"
)

// TestGUIWindowManagement tests the GUI window state tracking and management functions.
// Note: These tests verify the API behavior without actually creating GUI windows,
// as GUI tests require a graphical environment not available in CI.
func TestGUIWindowManagement(t *testing.T) {
	t.Run("HasGUIWindow returns false before initialization", func(t *testing.T) {
		container := newVirtualizationMachine(t)
		t.Cleanup(func() {
			if err := container.Shutdown(); err != nil {
				t.Log(err)
			}
		})

		if container.HasGUIWindow() {
			t.Error("HasGUIWindow should return false before StartGraphicApplication is called")
		}
	})

	t.Run("BringWindowToFront fails before GUI initialization", func(t *testing.T) {
		if !vz.Available(12) {
			t.Skip("BringWindowToFront requires macOS 12+")
		}

		container := newVirtualizationMachine(t)
		t.Cleanup(func() {
			if err := container.Shutdown(); err != nil {
				t.Log(err)
			}
		})

		err := container.BringWindowToFront()
		if err == nil {
			t.Error("BringWindowToFront should return error before GUI is initialized")
		}
		t.Logf("Got expected error: %v", err)
	})

	t.Run("ShowWindow fails before GUI initialization", func(t *testing.T) {
		if !vz.Available(12) {
			t.Skip("ShowWindow requires macOS 12+")
		}

		container := newVirtualizationMachine(t)
		t.Cleanup(func() {
			if err := container.Shutdown(); err != nil {
				t.Log(err)
			}
		})

		err := container.ShowWindow()
		if err == nil {
			t.Error("ShowWindow should return error before GUI is initialized")
		}
		t.Logf("Got expected error: %v", err)
	})
}

// TestStartGraphicApplicationOptions tests the option functions for StartGraphicApplication.
func TestStartGraphicApplicationOptions(t *testing.T) {
	t.Run("WithConfirmStopOnClose creates valid option", func(t *testing.T) {
		opt := vz.WithConfirmStopOnClose(true)
		if opt == nil {
			t.Error("WithConfirmStopOnClose(true) returned nil")
		}

		opt = vz.WithConfirmStopOnClose(false)
		if opt == nil {
			t.Error("WithConfirmStopOnClose(false) returned nil")
		}
	})

	t.Run("WithWindowTitle creates valid option", func(t *testing.T) {
		opt := vz.WithWindowTitle("Test VM")
		if opt == nil {
			t.Error("WithWindowTitle returned nil")
		}
	})

	t.Run("WithController creates valid option", func(t *testing.T) {
		opt := vz.WithController(true)
		if opt == nil {
			t.Error("WithController(true) returned nil")
		}

		opt = vz.WithController(false)
		if opt == nil {
			t.Error("WithController(false) returned nil")
		}
	})
}

// TestStartGraphicApplicationValidation documents input validation behavior.
// Note: Cannot actually test GUI creation without a graphical environment.
func TestStartGraphicApplicationValidation(t *testing.T) {
	if !vz.Available(12) {
		t.Skip("StartGraphicApplication requires macOS 12+")
	}

	tests := []struct {
		name   string
		width  float64
		height float64
		valid  bool
	}{
		{"valid dimensions", 800, 600, true},
		{"zero width", 0, 600, false},
		{"zero height", 800, 0, false},
		{"negative width", -800, 600, false},
		{"negative height", 800, -600, false},
		{"both zero", 0, 0, false},
		{"large dimensions", 3840, 2160, true},
		{"minimum dimensions", 1, 1, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Note: We can't actually test this without creating a GUI window,
			// which would block the test and require a graphical environment.
			// This is more of a documentation of expected behavior.
			if tt.width <= 0 || tt.height <= 0 {
				t.Logf("Would expect error for width=%v height=%v", tt.width, tt.height)
			}
		})
	}
}

// TestGUIWindowLifecycle documents the expected lifecycle behavior.
// This test cannot run in CI but documents the expected sequence.
func TestGUIWindowLifecycle(t *testing.T) {
	t.Skip("GUI lifecycle test requires graphical environment - documented here for manual testing")

	// Expected sequence:
	// 1. VM starts in stopped state
	// 2. Start() transitions to running
	// 3. StartGraphicApplication() creates window, sets hasGUIWindow=true
	// 4. HasGUIWindow() returns true
	// 5. BringWindowToFront() works
	// 6. User closes window -> triggers callback -> hasGUIWindow=false, VM stops
	// 7. HasGUIWindow() returns false after window closed
	//
	// Manual test checklist:
	// [ ] Create VM and start it
	// [ ] Call StartGraphicApplication with various options
	// [ ] Verify window appears with correct title
	// [ ] Verify toolbar buttons work (start/pause, input capture)
	// [ ] Call BringWindowToFront while window is hidden
	// [ ] Verify window comes to foreground
	// [ ] Close window with confirmation enabled
	// [ ] Verify confirmation dialog appears with localized text
	// [ ] Click "Cancel" - window should stay open
	// [ ] Close window again, click "Stop" - VM should stop
	// [ ] Verify HasGUIWindow returns false after close
	//
	// Localization test checklist:
	// [ ] Change system locale to each supported language
	// [ ] Verify confirmation dialog shows correct translation
	// [ ] Test fallback: set unsupported locale, verify English appears
}
