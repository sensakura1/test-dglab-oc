//go:build windows

package monitor

import (
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"unsafe"
)

var (
	user32                     = syscall.NewLazyDLL("user32.dll")
	kernel32                   = syscall.NewLazyDLL("kernel32.dll")
	getForegroundWindow        = user32.NewProc("GetForegroundWindow")
	getWindowTextLengthW       = user32.NewProc("GetWindowTextLengthW")
	getWindowTextW             = user32.NewProc("GetWindowTextW")
	getWindowThreadProcessID   = user32.NewProc("GetWindowThreadProcessId")
	enumWindows                = user32.NewProc("EnumWindows")
	isWindowVisible            = user32.NewProc("IsWindowVisible")
	getLastInputInfo           = user32.NewProc("GetLastInputInfo")
	openProcess                = kernel32.NewProc("OpenProcess")
	queryFullProcessImageNameW = kernel32.NewProc("QueryFullProcessImageNameW")
	closeHandle                = kernel32.NewProc("CloseHandle")
)

type lastInputInfo struct {
	Size uint32
	Time uint32
}

const processQueryLimitedInformation = 0x1000

type WindowInfo struct {
	Process string
	Title   string
}

func (w WindowInfo) Display() string {
	if strings.TrimSpace(w.Title) == "" {
		return w.Process
	}
	return w.Process + " | " + w.Title
}

func Foreground() WindowInfo {
	hwnd, _, _ := getForegroundWindow.Call()
	if hwnd == 0 {
		return WindowInfo{Process: "unknown"}
	}

	length, _, _ := getWindowTextLengthW.Call(hwnd)
	titleBuffer := make([]uint16, length+1)
	if len(titleBuffer) > 0 {
		getWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&titleBuffer[0])), uintptr(len(titleBuffer)))
	}

	var processID uint32
	getWindowThreadProcessID.Call(hwnd, uintptr(unsafe.Pointer(&processID)))
	return WindowInfo{
		Process: processName(processID),
		Title:   syscall.UTF16ToString(titleBuffer),
	}
}

func VisibleWindows() []WindowInfo {
	seen := map[string]bool{}
	result := make([]WindowInfo, 0, 32)
	callback := syscall.NewCallback(func(hwnd uintptr, _ uintptr) uintptr {
		visible, _, _ := isWindowVisible.Call(hwnd)
		if visible == 0 {
			return 1
		}
		length, _, _ := getWindowTextLengthW.Call(hwnd)
		if length == 0 {
			return 1
		}
		buffer := make([]uint16, length+1)
		getWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)))
		title := strings.TrimSpace(syscall.UTF16ToString(buffer))
		if title == "" {
			return 1
		}
		var processID uint32
		getWindowThreadProcessID.Call(hwnd, uintptr(unsafe.Pointer(&processID)))
		info := WindowInfo{Process: processName(processID), Title: title}
		key := info.Display()
		if !seen[key] {
			seen[key] = true
			result = append(result, info)
		}
		return 1
	})
	enumWindows.Call(callback, 0)
	sort.Slice(result, func(i, j int) bool { return result[i].Display() < result[j].Display() })
	return result
}

func IdleMilliseconds() uint32 {
	info := lastInputInfo{Size: uint32(unsafe.Sizeof(lastInputInfo{}))}
	ok, _, _ := getLastInputInfo.Call(uintptr(unsafe.Pointer(&info)))
	if ok == 0 {
		return 0
	}
	tick, _, _ := kernel32.NewProc("GetTickCount").Call()
	return uint32(tick) - info.Time
}

func processName(processID uint32) string {
	handle, _, _ := openProcess.Call(processQueryLimitedInformation, 0, uintptr(processID))
	if handle == 0 {
		return "unknown"
	}
	defer closeHandle.Call(handle)

	buffer := make([]uint16, 32768)
	size := uint32(len(buffer))
	ok, _, _ := queryFullProcessImageNameW.Call(
		handle,
		0,
		uintptr(unsafe.Pointer(&buffer[0])),
		uintptr(unsafe.Pointer(&size)),
	)
	if ok == 0 || size == 0 {
		return "unknown"
	}
	name := filepath.Base(syscall.UTF16ToString(buffer[:size]))
	return strings.TrimSuffix(name, filepath.Ext(name))
}
