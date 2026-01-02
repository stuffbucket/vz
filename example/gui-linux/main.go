package main

/*
#cgo darwin CFLAGS: -x objective-c
#cgo darwin LDFLAGS: -framework Cocoa
#include <stdlib.h>

// Defined in app_menu.m
void setupAppFileMenu(void);
*/
import "C"
import (
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/Code-Hex/vz/v3"
)

const isoEnvVar = "ISO"

// Channels for GUI menu events
var (
	createVMCh = make(chan [2]string, 10) // receives (isoPath, vmName)
	startVMCh  = make(chan [2]string, 10) // receives (vmName, isoPath)
)

// runningVMs tracks which VMs are currently running to prevent double-starts
var runningVMs = struct {
	sync.RWMutex
	names map[string]bool
}{names: make(map[string]bool)}

func markRunning(name string) bool {
	runningVMs.Lock()
	defer runningVMs.Unlock()
	if runningVMs.names[name] {
		return false // already running
	}
	runningVMs.names[name] = true
	return true
}

func markStopped(name string) {
	runningVMs.Lock()
	defer runningVMs.Unlock()
	delete(runningVMs.names, name)
}

func isRunning(name string) bool {
	runningVMs.RLock()
	defer runningVMs.RUnlock()
	return runningVMs.names[name]
}

// CGO exports for Obj-C menu callbacks

//export getVMListCallback
func getVMListCallback() *C.char {
	reg, err := LoadRegistry()
	if err != nil {
		return C.CString("")
	}
	var names []string
	for _, vm := range reg.List() {
		names = append(names, vm.Name)
	}
	result := strings.Join(names, "\n")
	return C.CString(result)
}

//export isVMRunningCallback
func isVMRunningCallback(vmNameCString *C.char) C.int {
	name := C.GoString(vmNameCString)
	if isRunning(name) {
		return 1
	}
	return 0
}

//export startVMGoCallback
func startVMGoCallback(vmNameCString *C.char, isoPathCString *C.char) {
	data := [2]string{C.GoString(vmNameCString), C.GoString(isoPathCString)}
	select {
	case startVMCh <- data:
	default:
	}
}

//export newVMFromURLGoCallback
func newVMFromURLGoCallback(isoPathCString *C.char, vmNameCString *C.char) {
	data := [2]string{C.GoString(isoPathCString), C.GoString(vmNameCString)}
	select {
	case createVMCh <- data:
	default:
	}
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `Usage: %s [command] [options]

Commands:
  (none)                        Open GUI with no VMs started
  start [name] [-iso path]      Start a VM (default: "default")
  create [name] -iso path       Create and start a new VM (default: "default")
  list                          List all VMs
  delete <name> [--force]       Delete a VM (--force stops if running)

Environment:
  ISO                           Default ISO path for start/create

Legacy:
  -install                      Start 'default' VM with INSTALLER_ISO_PATH env

Examples:
  %[1]s                              # Open GUI
  %[1]s start                        # Start 'default' VM
  %[1]s start myvm                   # Start existing VM
  %[1]s start myvm -iso boot.iso     # Start VM with ISO attached
  %[1]s create -iso boot.iso         # Create 'default' VM with ISO
  %[1]s create myvm -iso boot.iso    # Create new VM with ISO
  ISO=boot.iso %[1]s create myvm     # Create using env var
  %[1]s list                         # List all VMs
  %[1]s delete myvm                  # Delete a VM
  %[1]s delete myvm --force          # Stop and delete a running VM
`, os.Args[0])
}

// getISOPath returns ISO path from args or environment
func getISOPath(args []string) string {
	for i, arg := range args {
		if arg == "-iso" && i+1 < len(args) {
			return args[i+1]
		}
	}
	return os.Getenv(isoEnvVar)
}

// getNameArg returns the name argument (first non-flag arg after command)
func getNameArg(args []string) string {
	for _, arg := range args {
		if !strings.HasPrefix(arg, "-") {
			return arg
		}
	}
	return ""
}

func run() error {
	registry, err := LoadRegistry()
	if err != nil {
		return fmt.Errorf("failed to load registry: %w", err)
	}

	// No args = open GUI with no VMs
	if len(os.Args) < 2 {
		return runGUIOnly(registry)
	}

	cmd := os.Args[1]
	args := os.Args[2:] // args after command

	// Legacy -install flag
	if cmd == "-install" {
		envISO := os.Getenv("INSTALLER_ISO_PATH")
		if envISO == "" {
			return fmt.Errorf("must specify INSTALLER_ISO_PATH env with -install")
		}
		return runStartCommand(registry, DefaultVMName, envISO)
	}

	switch cmd {
	case "start":
		name := getNameArg(args)
		if name == "" {
			name = DefaultVMName
		}
		iso := getISOPath(args)
		return runStartCommand(registry, name, iso)

	case "create":
		name := getNameArg(args)
		if name == "" {
			name = DefaultVMName
		}
		iso := getISOPath(args)
		if iso == "" {
			return fmt.Errorf("ISO required: use -iso <path> or set ISO env var")
		}
		return runCreateCommand(registry, name, iso)

	case "list":
		return runListCommand(registry)

	case "delete":
		name := getNameArg(args)
		if name == "" {
			return fmt.Errorf("usage: %s delete <name> [--force]", os.Args[0])
		}
		force := false
		for _, arg := range args {
			if arg == "--force" || arg == "-f" {
				force = true
			}
		}
		return runDeleteCommand(registry, name, force)

	case "-h", "--help", "help":
		usage()
		return nil

	default:
		usage()
		return fmt.Errorf("unknown command: %s", cmd)
	}
}

func runGUIOnly(registry *Registry) error {
	log.Printf("Starting GUI (no VM)")
	return runEventLoop(registry, nil)
}

func runStartCommand(registry *Registry, name, isoPath string) error {
	entry := registry.Find(name)
	if entry == nil {
		return fmt.Errorf("VM %q not found. Use 'create' to create it", name)
	}

	if isRunning(name) {
		return fmt.Errorf("VM %q is already running", name)
	}

	bundle := registry.BundleFor(entry)

	// Expand ~ in ISO path
	if strings.HasPrefix(isoPath, "~/") {
		home, _ := os.UserHomeDir()
		isoPath = filepath.Join(home, isoPath[2:])
	}

	// Use provided ISO, or fall back to stored ISO if disk is empty
	effectiveISO := isoPath
	if effectiveISO == "" && entry.ISOPath != "" && !bundle.HasBootableDisk() {
		effectiveISO = entry.ISOPath
		log.Printf("Using stored ISO: %s", effectiveISO)
	}

	return runEventLoop(registry, &vmStartRequest{
		entry:   entry,
		bundle:  bundle,
		isoPath: effectiveISO,
	})
}

func runCreateCommand(registry *Registry, name, isoPath string) error {
	if registry.Exists(name) {
		return fmt.Errorf("VM %q already exists", name)
	}

	// Expand ~ in ISO path
	if strings.HasPrefix(isoPath, "~/") {
		home, _ := os.UserHomeDir()
		isoPath = filepath.Join(home, isoPath[2:])
	}

	// Verify ISO exists
	if _, err := os.Stat(isoPath); os.IsNotExist(err) {
		return fmt.Errorf("ISO not found: %s", isoPath)
	}

	entry, err := registry.Add(name, isoPath)
	if err != nil {
		return fmt.Errorf("failed to create VM: %w", err)
	}

	bundle := registry.BundleFor(entry)
	if err := bundle.Create(); err != nil {
		return fmt.Errorf("failed to create bundle: %w", err)
	}

	fmt.Printf("Created VM %q\n", name)
	return runEventLoop(registry, &vmStartRequest{
		entry:   entry,
		bundle:  bundle,
		isoPath: isoPath,
	})
}

func runListCommand(registry *Registry) error {
	vms := registry.List()
	if len(vms) == 0 {
		fmt.Println("No VMs configured.")
		return nil
	}

	fmt.Println("Virtual Machines:")
	for _, vm := range vms {
		bundle := registry.BundleFor(&vm)
		status := "ready"
		if !bundle.HasBootableDisk() && vm.ISOPath != "" {
			status = "needs boot media"
		}
		iso := ""
		if vm.ISOPath != "" {
			iso = fmt.Sprintf(" (iso: %s)", vm.ISOPath)
		}
		fmt.Printf("  %s [%s]%s\n", vm.Name, status, iso)
	}
	return nil
}

func runDeleteCommand(registry *Registry, name string, force bool) error {
	if !registry.Exists(name) {
		return fmt.Errorf("VM %q not found", name)
	}

	if isRunning(name) {
		if !force {
			return fmt.Errorf("VM %q is running. Use --force to stop and delete", name)
		}
		// TODO: actually stop the VM
		// For now, just warn - we can't stop VMs from CLI in this process
		return fmt.Errorf("VM %q is running in another process. Stop it first or use the GUI", name)
	}

	fmt.Printf("Delete VM %q and all its data? (yes/no): ", name)
	var confirm string
	fmt.Scanln(&confirm)
	if confirm != "yes" {
		fmt.Println("Cancelled.")
		return nil
	}

	if err := registry.Remove(name, true); err != nil {
		return fmt.Errorf("failed to delete VM: %w", err)
	}
	fmt.Printf("Deleted VM %q\n", name)
	return nil
}

// vmStartRequest holds info for starting a VM on event loop start
type vmStartRequest struct {
	entry   *VMEntry
	bundle  *Bundle
	isoPath string
}

// runEventLoop sets up providers and runs the AppKit event loop
func runEventLoop(registry *Registry, initialVM *vmStartRequest) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	// Start listening for GUI menu events
	go handleCreateVMRequests()
	go handleStartVMRequests()

	// Start initial VM if requested
	if initialVM != nil {
		needsInstall := initialVM.isoPath != ""
		log.Printf("Starting VM %q (needsInstall=%v)", initialVM.entry.Name, needsInstall)
		if err := createAndShowVM(initialVM.isoPath, needsInstall, initialVM.entry.Name, initialVM.bundle); err != nil {
			return err
		}
	}

	// Set up app-specific File menu (must happen after RunApplication initializes the app)
	// We do this in a goroutine that waits for the main menu to exist
	go func() {
		// Small delay to ensure app is initialized
		runtime.LockOSThread()
		C.setupAppFileMenu()
	}()

	log.Printf("Running application event loop...")
	return vz.RunApplication()
}

func handleStartVMRequests() {
	for data := range startVMCh {
		vmName, isoPath := data[0], data[1]
		log.Printf("Start VM request: name=%s iso=%s", vmName, isoPath)

		registry, err := LoadRegistry()
		if err != nil {
			log.Printf("Failed to reload registry: %v", err)
			continue
		}

		entry := registry.Find(vmName)
		if entry == nil {
			log.Printf("VM %q not found", vmName)
			continue
		}

		if isRunning(vmName) {
			log.Printf("VM %q is already running", vmName)
			continue
		}

		bundle := registry.BundleFor(entry)

		// Use provided ISO, or fall back to stored ISO if disk is empty
		effectiveISO := isoPath
		if effectiveISO == "" && entry.ISOPath != "" && !bundle.HasBootableDisk() {
			effectiveISO = entry.ISOPath
			log.Printf("Using stored ISO: %s", effectiveISO)
		}
		needsInstall := effectiveISO != ""

		if err := createAndShowVM(effectiveISO, needsInstall, entry.Name, bundle); err != nil {
			log.Printf("Failed to start VM %q: %v", vmName, err)
		}
	}
}

func handleCreateVMRequests() {
	for data := range createVMCh {
		isoPath, vmName := data[0], data[1]
		log.Printf("Create VM request: name=%s iso=%s", vmName, isoPath)

		registry, err := LoadRegistry()
		if err != nil {
			log.Printf("Failed to reload registry: %v", err)
			continue
		}

		// Check if VM already exists
		if registry.Exists(vmName) {
			log.Printf("VM %q already exists in registry", vmName)
			continue
		}

		// Check if already running (shouldn't be possible but be safe)
		if isRunning(vmName) {
			log.Printf("VM %q is already running", vmName)
			continue
		}

		entry, err := registry.Add(vmName, isoPath)
		if err != nil {
			log.Printf("Failed to create VM entry: %v", err)
			continue
		}

		bundle := registry.BundleFor(entry)
		if err := bundle.Create(); err != nil {
			log.Printf("Failed to create bundle: %v", err)
			continue
		}

		if err := createAndShowVM(isoPath, true, entry.Name, bundle); err != nil {
			log.Printf("Failed to create VM from %s: %v", isoPath, err)
		}
	}
}

func createAndShowVM(isoPath string, needsInstall bool, title string, bundle *Bundle) error {
	// Mark VM as running (prevent double-start)
	if !markRunning(title) {
		return fmt.Errorf("VM %q is already running", title)
	}

	config, err := createVirtualMachineConfig(isoPath, needsInstall, bundle)
	if err != nil {
		markStopped(title)
		return fmt.Errorf("failed to create VM config: %w", err)
	}

	vm, err := vz.NewVirtualMachine(config)
	if err != nil {
		markStopped(title)
		return fmt.Errorf("failed to create VM: %w", err)
	}

	if err := vm.Start(); err != nil {
		markStopped(title)
		return fmt.Errorf("failed to start VM: %w", err)
	}

	// Monitor VM state in background
	go func() {
		for state := range vm.StateChangedNotify() {
			log.Printf("[%s] VM state: %v", title, state)
			if state == vz.VirtualMachineStateStopped {
				markStopped(title)
				return
			}
		}
	}()

	// Create window (non-blocking, window shows immediately)
	if err := vm.CreateWindow(960, 600, vz.WithWindowTitle(title), vz.WithController(true)); err != nil {
		markStopped(title)
		return fmt.Errorf("failed to create window: %w", err)
	}

	log.Printf("[%s] VM started", title)
	return nil
}

// Create an empty disk image for the virtual machine.
func createMainDiskImage(diskPath string) error {
	// create disk image with 64 GiB
	if err := vz.CreateDiskImage(diskPath, 64*1024*1024*1024); err != nil {
		if !os.IsExist(err) {
			return fmt.Errorf("failed to create disk image: %w", err)
		}
	}
	return nil
}

func createBlockDeviceConfiguration(diskPath string) (*vz.VirtioBlockDeviceConfiguration, error) {
	attachment, err := vz.NewDiskImageStorageDeviceAttachmentWithCacheAndSync(diskPath, false, vz.DiskImageCachingModeAutomatic, vz.DiskImageSynchronizationModeFsync)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new disk image storage device attachment: %w", err)
	}
	mainDisk, err := vz.NewVirtioBlockDeviceConfiguration(attachment)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new block deveice config: %w", err)
	}
	return mainDisk, nil
}

func computeCPUCount() uint {
	totalAvailableCPUs := runtime.NumCPU()
	virtualCPUCount := uint(totalAvailableCPUs - 1)
	if virtualCPUCount <= 1 {
		virtualCPUCount = 1
	}
	maxAllowed := vz.VirtualMachineConfigurationMaximumAllowedCPUCount()
	if virtualCPUCount > maxAllowed {
		virtualCPUCount = maxAllowed
	}
	minAllowed := vz.VirtualMachineConfigurationMinimumAllowedCPUCount()
	if virtualCPUCount < minAllowed {
		virtualCPUCount = minAllowed
	}
	return virtualCPUCount
}

func computeMemorySize() uint64 {
	memorySize := uint64(4 * 1024 * 1024 * 1024)
	maxAllowed := vz.VirtualMachineConfigurationMaximumAllowedMemorySize()
	if memorySize > maxAllowed {
		memorySize = maxAllowed
	}
	minAllowed := vz.VirtualMachineConfigurationMinimumAllowedMemorySize()
	if memorySize < minAllowed {
		memorySize = minAllowed
	}
	return memorySize
}

func createAndSaveMachineIdentifier(identifierPath string) (*vz.GenericMachineIdentifier, error) {
	machineIdentifier, err := vz.NewGenericMachineIdentifier()
	if err != nil {
		return nil, fmt.Errorf("failed to create a new machine identifier: %w", err)
	}
	err = CreateFileAndWriteTo(machineIdentifier.DataRepresentation(), identifierPath)
	if err != nil {
		return nil, fmt.Errorf("failed to save machine identifier data: %w", err)
	}
	return machineIdentifier, nil
}

func createEFIVariableStore(efiVariableStorePath string) (*vz.EFIVariableStore, error) {
	variableStore, err := vz.NewEFIVariableStore(
		efiVariableStorePath,
		vz.WithCreatingEFIVariableStore(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create EFI variable store: %w", err)
	}
	return variableStore, nil
}

func createUSBMassStorageDeviceConfiguration(installerISOPath string) (*vz.USBMassStorageDeviceConfiguration, error) {
	installerDiskAttachment, err := vz.NewDiskImageStorageDeviceAttachment(
		installerISOPath,
		true,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new disk attachment for USBMassConfiguration: %w", err)
	}
	config, err := vz.NewUSBMassStorageDeviceConfiguration(installerDiskAttachment)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new USB storage device: %w", err)
	}
	return config, nil
}

func createNetworkDeviceConfiguration() (*vz.VirtioNetworkDeviceConfiguration, error) {
	natAttachment, err := vz.NewNATNetworkDeviceAttachment()
	if err != nil {
		return nil, fmt.Errorf("nat attachment initialization failed: %w", err)
	}
	netConfig, err := vz.NewVirtioNetworkDeviceConfiguration(natAttachment)
	if err != nil {
		return nil, fmt.Errorf("failed to create a network device: %w", err)
	}
	return netConfig, nil
}

func createGraphicsDeviceConfiguration() (*vz.VirtioGraphicsDeviceConfiguration, error) {
	graphicDeviceConfig, err := vz.NewVirtioGraphicsDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize virtio graphic device: %w", err)
	}
	graphicsScanoutConfig, err := vz.NewVirtioGraphicsScanoutConfiguration(1920, 1200)
	if err != nil {
		return nil, fmt.Errorf("failed to create graphics scanout: %w", err)
	}
	graphicDeviceConfig.SetScanouts(
		graphicsScanoutConfig,
	)
	return graphicDeviceConfig, nil
}

func createInputAudioDeviceConfiguration() (*vz.VirtioSoundDeviceConfiguration, error) {
	audioConfig, err := vz.NewVirtioSoundDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create sound device configuration: %w", err)
	}
	inputStream, err := vz.NewVirtioSoundDeviceHostInputStreamConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create input stream configuration: %w", err)
	}
	audioConfig.SetStreams(
		inputStream,
	)
	return audioConfig, nil
}

func createOutputAudioDeviceConfiguration() (*vz.VirtioSoundDeviceConfiguration, error) {
	audioConfig, err := vz.NewVirtioSoundDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create sound device configuration: %w", err)
	}
	outputStream, err := vz.NewVirtioSoundDeviceHostOutputStreamConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create output stream configuration: %w", err)
	}
	audioConfig.SetStreams(
		outputStream,
	)
	return audioConfig, nil
}

func createSpiceAgentConsoleDeviceConfiguration() (*vz.VirtioConsoleDeviceConfiguration, error) {
	consoleDevice, err := vz.NewVirtioConsoleDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create a new console device: %w", err)
	}

	spiceAgentAttachment, err := vz.NewSpiceAgentPortAttachment()
	if err != nil {
		return nil, fmt.Errorf("failed to create a new spice agent attachment: %w", err)
	}
	spiceAgentName, err := vz.SpiceAgentPortAttachmentName()
	if err != nil {
		return nil, fmt.Errorf("failed to get spice agent name: %w", err)
	}
	spiceAgentPort, err := vz.NewVirtioConsolePortConfiguration(
		vz.WithVirtioConsolePortConfigurationAttachment(spiceAgentAttachment),
		vz.WithVirtioConsolePortConfigurationName(spiceAgentName),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new console port for spice agent: %w", err)
	}

	consoleDevice.SetVirtioConsolePortConfiguration(0, spiceAgentPort)

	return consoleDevice, nil
}

// createVirtualMachineConfig creates a VM config using the specified bundle
func createVirtualMachineConfig(installerISOPath string, needsInstall bool, bundle *Bundle) (*vz.VirtualMachineConfiguration, error) {
	var machineIdentifier *vz.GenericMachineIdentifier
	var err error
	if needsInstall {
		machineIdentifier, err = createAndSaveMachineIdentifier(bundle.MachineIdentifierPath())
	} else {
		machineIdentifier, err = vz.NewGenericMachineIdentifierWithDataPath(bundle.MachineIdentifierPath())
	}
	if err != nil {
		return nil, err
	}

	platformConfig, err := vz.NewGenericPlatformConfiguration(
		vz.WithGenericMachineIdentifier(machineIdentifier),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new platform config: %w", err)
	}

	var efiVariableStore *vz.EFIVariableStore
	if needsInstall {
		efiVariableStore, err = createEFIVariableStore(bundle.EFIVariableStorePath())
	} else {
		efiVariableStore, err = vz.NewEFIVariableStore(bundle.EFIVariableStorePath())
	}
	if err != nil {
		return nil, err
	}

	bootLoader, err := vz.NewEFIBootLoader(
		vz.WithEFIVariableStore(efiVariableStore),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create a new EFI boot loader: %w", err)
	}

	disks := make([]vz.StorageDeviceConfiguration, 0)
	if needsInstall {
		usbConfig, err := createUSBMassStorageDeviceConfiguration(installerISOPath)
		if err != nil {
			return nil, err
		}
		disks = append(disks, usbConfig)
	}

	config, err := vz.NewVirtualMachineConfiguration(
		bootLoader,
		computeCPUCount(),
		computeMemorySize(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create vm config: %w", err)
	}

	config.SetPlatformVirtualMachineConfiguration(platformConfig)

	// Set graphic device
	graphicsDeviceConfig, err := createGraphicsDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create graphics device configuration: %w", err)
	}
	config.SetGraphicsDevicesVirtualMachineConfiguration([]vz.GraphicsDeviceConfiguration{
		graphicsDeviceConfig,
	})

	// Set storage device
	if needsInstall {
		if err := createMainDiskImage(bundle.DiskImagePath()); err != nil {
			return nil, fmt.Errorf("failed to create a main disk image: %w", err)
		}
	}
	mainDisk, err := createBlockDeviceConfiguration(bundle.DiskImagePath())
	if err != nil {
		return nil, err
	}
	disks = append(disks, mainDisk)
	config.SetStorageDevicesVirtualMachineConfiguration(disks)

	consoleDeviceConfig, err := createSpiceAgentConsoleDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create console device configuration: %w", err)
	}
	config.SetConsoleDevicesVirtualMachineConfiguration([]vz.ConsoleDeviceConfiguration{
		consoleDeviceConfig,
	})

	// Set network device
	networkDeviceConfig, err := createNetworkDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create network device configuration: %w", err)
	}
	config.SetNetworkDevicesVirtualMachineConfiguration([]*vz.VirtioNetworkDeviceConfiguration{
		networkDeviceConfig,
	})

	// Set audio device
	inputAudioDeviceConfig, err := createInputAudioDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create input audio device configuration: %w", err)
	}
	outputAudioDeviceConfig, err := createOutputAudioDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create output audio device configuration: %w", err)
	}
	config.SetAudioDevicesVirtualMachineConfiguration([]vz.AudioDeviceConfiguration{
		inputAudioDeviceConfig,
		outputAudioDeviceConfig,
	})

	// Set pointing device
	pointingDeviceConfig, err := vz.NewUSBScreenCoordinatePointingDeviceConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create pointing device configuration: %w", err)
	}
	config.SetPointingDevicesVirtualMachineConfiguration([]vz.PointingDeviceConfiguration{
		pointingDeviceConfig,
	})

	// Set keyboard device
	keyboardDeviceConfig, err := vz.NewUSBKeyboardConfiguration()
	if err != nil {
		return nil, fmt.Errorf("failed to create keyboard device configuration: %w", err)
	}
	config.SetKeyboardsVirtualMachineConfiguration([]vz.KeyboardConfiguration{
		keyboardDeviceConfig,
	})

	// Set rosetta directory share
	directorySharingConfigs := make([]vz.DirectorySharingDeviceConfiguration, 0)
	directorySharingDeviceConfig, err := createRosettaDirectoryShareConfiguration()
	if err != nil && !errors.Is(err, errIgnoreInstall) {
		return nil, err
	}
	if directorySharingDeviceConfig != nil {
		directorySharingConfigs = append(directorySharingConfigs, directorySharingDeviceConfig)
	}

	config.SetDirectorySharingDevicesVirtualMachineConfiguration(directorySharingConfigs)

	validated, err := config.Validate()
	if err != nil {
		return nil, fmt.Errorf("failed to validate configuration: %w", err)
	}
	if !validated {
		return nil, fmt.Errorf("invalid configuration")
	}

	return config, nil
}
