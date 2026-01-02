package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// Bundle represents a VM bundle directory containing disk, EFI, and machine ID.
type Bundle struct {
	Path string
}

// NewBundle creates a bundle at the specified path.
func NewBundle(path string) *Bundle {
	return &Bundle{Path: path}
}

// Create creates the bundle directory if it doesn't exist.
func (b *Bundle) Create() error {
	return os.MkdirAll(b.Path, 0755)
}

// Exists returns true if the bundle directory exists.
func (b *Bundle) Exists() bool {
	_, err := os.Stat(b.Path)
	return err == nil
}

// DiskImagePath returns the path to the disk image.
func (b *Bundle) DiskImagePath() string {
	return filepath.Join(b.Path, "Disk.img")
}

// EFIVariableStorePath returns the path to the EFI variable store.
func (b *Bundle) EFIVariableStorePath() string {
	return filepath.Join(b.Path, "NVRAM")
}

// MachineIdentifierPath returns the path to the machine identifier.
func (b *Bundle) MachineIdentifierPath() string {
	return filepath.Join(b.Path, "MachineIdentifier")
}

// IsInstalled returns true if the bundle has been initialized (has NVRAM).
func (b *Bundle) IsInstalled() bool {
	_, err := os.Stat(b.EFIVariableStorePath())
	return err == nil
}

// HasBootableDisk returns true if the disk image appears to have an OS installed.
// This is a heuristic - checks if disk exists and has non-zero data in first sector.
func (b *Bundle) HasBootableDisk() bool {
	f, err := os.Open(b.DiskImagePath())
	if err != nil {
		return false
	}
	defer f.Close()

	// Read first 512 bytes (boot sector)
	buf := make([]byte, 512)
	n, err := f.Read(buf)
	if err != nil || n < 512 {
		return false
	}

	// Check if it's all zeros (empty disk)
	for _, b := range buf {
		if b != 0 {
			return true
		}
	}
	return false
}

// CreateFileAndWriteTo creates a new file and writes data to it.
func CreateFileAndWriteTo(data []byte, path string) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("failed to create file %q: %w", path, err)
	}
	defer f.Close()

	_, err = f.Write(data)
	if err != nil {
		return fmt.Errorf("failed to write data: %w", err)
	}
	return nil
}
