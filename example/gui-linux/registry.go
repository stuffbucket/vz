package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const (
	BaseDirectoryName = "GUI Linux VM"
	RegistryFileName  = "registry.json"
	DefaultVMName     = "default"
)

// VMEntry represents a registered virtual machine.
type VMEntry struct {
	Name       string    `json:"name"`
	BundleName string    `json:"bundle_name"`        // relative to base dir, e.g., "default.bundle"
	ISOPath    string    `json:"iso_path,omitempty"` // path to ISO used for creation/live boot
	CreatedAt  time.Time `json:"created_at"`
}

// Registry tracks all VMs in the base directory.
type Registry struct {
	VMs  []VMEntry `json:"vms"`
	path string    // path to registry.json
}

// BaseDirectory returns the base directory for all VMs.
func BaseDirectory() string {
	home, err := os.UserHomeDir()
	if err != nil {
		home = os.Getenv("HOME")
	}
	return filepath.Join(home, BaseDirectoryName)
}

// EnsureBaseDirectory creates the base directory if it doesn't exist.
func EnsureBaseDirectory() error {
	return os.MkdirAll(BaseDirectory(), 0755)
}

// RegistryPath returns the path to registry.json.
func RegistryPath() string {
	return filepath.Join(BaseDirectory(), RegistryFileName)
}

// LoadRegistry loads or creates the registry.
func LoadRegistry() (*Registry, error) {
	if err := EnsureBaseDirectory(); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}

	r := &Registry{
		VMs:  []VMEntry{},
		path: RegistryPath(),
	}

	data, err := os.ReadFile(r.path)
	if os.IsNotExist(err) {
		return r, nil // empty registry
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read registry: %w", err)
	}

	if err := json.Unmarshal(data, r); err != nil {
		return nil, fmt.Errorf("failed to parse registry: %w", err)
	}

	return r, nil
}

// Save writes the registry to disk.
func (r *Registry) Save() error {
	data, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal registry: %w", err)
	}
	if err := os.WriteFile(r.path, data, 0644); err != nil {
		return fmt.Errorf("failed to write registry: %w", err)
	}
	return nil
}

// Find returns the VM entry with the given name, or nil if not found.
func (r *Registry) Find(name string) *VMEntry {
	for i := range r.VMs {
		if r.VMs[i].Name == name {
			return &r.VMs[i]
		}
	}
	return nil
}

// Exists returns true if a VM with the given name exists.
func (r *Registry) Exists(name string) bool {
	return r.Find(name) != nil
}

// Add creates a new VM entry. Returns error if name already exists.
func (r *Registry) Add(name string, isoPath string) (*VMEntry, error) {
	if r.Exists(name) {
		return nil, fmt.Errorf("VM %q already exists", name)
	}

	entry := VMEntry{
		Name:       name,
		BundleName: name + ".bundle",
		ISOPath:    isoPath,
		CreatedAt:  time.Now(),
	}
	r.VMs = append(r.VMs, entry)

	if err := r.Save(); err != nil {
		// rollback
		r.VMs = r.VMs[:len(r.VMs)-1]
		return nil, err
	}

	return &entry, nil
}

// Remove deletes a VM entry and optionally its bundle.
func (r *Registry) Remove(name string, deleteBundle bool) error {
	idx := -1
	for i := range r.VMs {
		if r.VMs[i].Name == name {
			idx = i
			break
		}
	}
	if idx == -1 {
		return fmt.Errorf("VM %q not found", name)
	}

	entry := r.VMs[idx]

	if deleteBundle {
		bundlePath := filepath.Join(BaseDirectory(), entry.BundleName)
		if err := os.RemoveAll(bundlePath); err != nil {
			return fmt.Errorf("failed to delete bundle: %w", err)
		}
	}

	r.VMs = append(r.VMs[:idx], r.VMs[idx+1:]...)
	return r.Save()
}

// List returns all VM entries.
func (r *Registry) List() []VMEntry {
	return r.VMs
}

// BundleFor returns a Bundle for the given VM entry.
func (r *Registry) BundleFor(entry *VMEntry) *Bundle {
	return NewBundle(filepath.Join(BaseDirectory(), entry.BundleName))
}

// GetOrCreateDefault returns the default VM, creating it if necessary.
func (r *Registry) GetOrCreateDefault() (*VMEntry, error) {
	if entry := r.Find(DefaultVMName); entry != nil {
		return entry, nil
	}
	return r.Add(DefaultVMName, "")
}

// UpdateISO updates the ISO path for a VM entry.
func (r *Registry) UpdateISO(name, isoPath string) error {
	entry := r.Find(name)
	if entry == nil {
		return fmt.Errorf("VM %q not found", name)
	}
	entry.ISOPath = isoPath
	return r.Save()
}
