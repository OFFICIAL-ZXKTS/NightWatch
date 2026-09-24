<div align="center">

<img src="assets/icon.png" width="140" height="140" alt="NightWatch Logo" />

# ðŸ›¡ï¸ NightWatch

### *Smart Study-Break & Battery-Preserving Idle Sentinel for Windows 11*

[![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%7C%2010-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://microsoft.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-Apache%202.0-D22128?style=for-the-badge&logo=apache&logoColor=white)](LICENSE)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-Yes-brightgreen?style=for-the-badge)](https://github.com/OFFICIAL-ZXKTS/NightWatch)

<p align="center">
  <b>Never wake up to a dead laptop battery or lost study session again.</b><br>
  Differentiates between intentional study breaks and accidentally falling asleep.
</p>

[Key Features](#-key-features) â€¢ [How It Works](#-how-it-works) â€¢ [Desktop Icon](#-custom-desktop-icon) â€¢ [Quick Installation](#-quick-installation) â€¢ [Usage](#-usage) â€¢ [FAQ](#-frequently-asked-questions) â€¢ [Uninstallation](#-uninstallation)

</div>

---

## âš¡ The Big Idea: A "Dead Man's Switch" for Late-Night Studying

Think of **NightWatch** as an intelligent safety switch for your **PC**:

| Your Action | Laptop's Interpretation | What Happens |
| :--- | :--- | :--- |
| ðŸŸ¢ **You Click the Button** (or press `Ctrl+Alt+B`) | **"I am on an intentional break â€” DO NOT shut down my PC!"** | Sends the break signal. Your PC **stays ON and active** (does not force sleep), but the 30-minute auto-shutdown is **PAUSED**. Your downloads and music keep running safely. |
| ðŸ”´ **You Do NOTHING** (Accidentally fell asleep) | **"No break signal received and 30m idle â€” user fell asleep!"** | The background watcher activates after 30 minutes of complete inactivity and **executes a clean forced shutdown** to protect your battery and SSD. |

---

## ðŸŽ¯ The Problem NightWatch Solves

When working late on your PC, you face a dilemma:
1. **If you step away for a break**: You want your computer to stay on and active without Windows auto-shutting down your 20 research tabs, background tasks, or unsaved work.
2. **If you accidentally fall asleep**: You don't want your laptop/PC burning all night on your bed or desk, draining battery cycles, overheating, and wearing out hardware.

**NightWatch gives you the best of both worlds with zero friction.**

```mermaid
graph TD
    A[You Step Away From PC] --> B{Did you click 'Study Break'?}
    
    B -- YES: 'Don't shut down, I'm on break!' --> C[Break signal active on Desktop]
    C --> D[PC stays ON normally: No forced sleep!]
    D --> E[After 30 mins idle -> Watcher sees signal]
    E --> F[Auto-Shutdown is SKIPPED -> PC stays safe!]

    B -- NO: You fell asleep (Dead Silence) --> G[Computer idles for 30 minutes]
    G --> H[Watcher checks: Was break signal given?]
    H -- NO SIGNAL FOUND --> I[Clean Forced Shutdown: Battery & SSD Protected!]
```

---

## âœ¨ Key Features

- **ðŸŽ¯ True 30-Minute Physical Idle Tracking**: Uses Win32 `GetLastInputInfo` to measure exact keyboard and mouse idle time. Immune to Windows 11 false alarms (no more premature shutdowns at 10 minutes when your screen dims!).
- **ðŸ”Š 30-Second Warning Beep Countdown**: Plays audible warning beeps before shutting down. Moving the mouse or tapping any key during the beeps instantly aborts the shutdown!
- **â˜• Bulletproof Break Mode**: Toggle on break mode with **`Ctrl + Alt + B`** or by double-clicking the custom icon. Immune to rapid double-clicks (debounce guard), keeps PC alive throughout your break, and auto-resumes protection once you return and type.
- **ðŸ›¡ï¸ Accidental Sleep Defense**: If you truly fall asleep with no break active, NightWatch executes a clean forced shutdown (`shutdown /s /f /t 0`) to protect your battery and SSD.
- **â˜ï¸ Cloud & OneDrive Aware**: Automatically detects both native and OneDrive-redirected Windows 11 Desktop environments.
- **ðŸ”‹ Full Battery & AC Support**: Configured to run whether on laptop battery or plugged into wall power.
- **âš™ï¸ Purely Administrative**: Runs elevated in the background via Task Scheduler with zero manual maintenance needed.

---

## ðŸ“¦ Project Structure

```text
NightWatch/
â”œâ”€â”€ assets/
â”‚   â”œâ”€â”€ icon.png                # High-res 3D preview logo
â”‚   â””â”€â”€ icon.ico                # Windows 256x256 desktop shortcut icon
â”œâ”€â”€ StudyBreak.ps1              # Core logic: Signals break mode & pauses shutdown
â”œâ”€â”€ StudyBreak.bat              # Standalone batch launcher
â”œâ”€â”€ IdleMistakeDetector.ps1     # 30-minute idle watcher & safety shutdown engine
â”œâ”€â”€ SilentRunner.vbs            # Zero-window invisible launcher for Task Scheduler
â”œâ”€â”€ Install-StudySafetySystem.ps1 # Automated installer (configures Task Scheduler & custom icon)
â”œâ”€â”€ Reinstall.bat               # 1-click self-elevating reinstaller
â”œâ”€â”€ Uninstall-StudySafetySystem.ps1 # One-click removal script
â”œâ”€â”€ LICENSE                     # Official Apache 2.0 License
â””â”€â”€ README.md                   # Documentation
```

---

## ðŸŽ¨ Custom Desktop Icon

NightWatch includes a custom-designed 3D app icon representing late-night study and sleep safety:

<div align="center">
  <img src="assets/icon.png" width="120" height="120" alt="NightWatch Icon" /><br>
  <sub><b>assets/icon.ico</b> (256x256 high-resolution Windows icon)</sub>
</div>

### How the icon is applied:
- **Automatic:** Running `Install-StudySafetySystem.ps1` or double-clicking `Reinstall.bat` automatically binds `assets\icon.ico` to your Desktop shortcut!
- **Manual (Optional):**
  1. Right-click the **Study Break** shortcut on your Desktop $\rightarrow$ select **Properties**.
  2. Under the **Shortcut** tab, click **Change Icon...**.
  3. Click **Browse...** $\rightarrow$ choose `assets\icon.ico` from your NightWatch folder.
  4. Click **OK** $\rightarrow$ **Apply**.

---

## ðŸš€ Quick Installation

### Option 1: Automated 1-Command Setup (Recommended)

1. Clone or download this repository.
2. Open **PowerShell as Administrator** (`Win + X` $\rightarrow$ **Terminal (Admin)**).
3. Navigate to your NightWatch folder and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Install-StudySafetySystem.ps1
```

The installer will automatically:
- Enable Windows Deep Hibernation (`powercfg /hibernate on`).
- Create your **Study Break** Desktop icon with the custom 3D icon and `Ctrl + Alt + B` hotkey.
- Register the 30-minute idle detector in Windows Task Scheduler with full battery support.

---

### Option 2: Manual Setup via Windows Task Scheduler

<details>
<summary>Click to view manual step-by-step instructions</summary>

> Only follow these steps if `Install-StudySafetySystem.ps1` failed for some reason
> and you want to recreate the task by hand. The task name and trigger type must
> match exactly, otherwise `IdleMistakeDetector.ps1` will not run on cadence.

1. **Enable Hibernation**:
   In an *Administrator* PowerShell or cmd: `powercfg /hibernate on`
2. **Create the Desktop Shortcut** (optional):
   - Right-click Desktop $\rightarrow$ **New** $\rightarrow$ **Shortcut**.
   - Location: `powershell.exe`
   - (Then set its *Target* properties â†’ *Target* field) to:
     `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<your-path>\StudyBreak.ps1"`
   - (Optional) set *Change Icon* to your cloned `assets\icon.ico`.
   - Name the shortcut `Study Break`.
3. **Register the scheduled task**:
   - Open `taskschd.msc` â†’ **Create Taskâ€¦** (not "Create Basic Task").
   - **General** tab:
     - **Name**: `NightWatchSentinel`
     - Select *Run only when user is logged on*
     - Check *Run with highest privileges*
   - **Triggers** tab â†’ **Newâ€¦**:
     - Begin the task: *On a schedule* â†’ *Daily*
     - **Advanced settings**: check *Repeat task every:* `1 minute`, for a *duration of:* `Indefinitely`.
   - **Actions** tab â†’ **Newâ€¦**:
     - Action: *Start a program*
     - Program/script: `powershell.exe`
     - Add arguments:
       `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<your-path>\IdleMistakeDetector.ps1"`
   - **Conditions** tab:
     - **Uncheck** *Start the task only if the computer is on AC power*
     - Leave all other boxes unchecked.
   - Click **OK** and supply your admin password if prompted.

The idle threshold itself is *not* a scheduler setting (it lives in the script as
`$targetIdleSeconds = 1800`); see [Customization](#-customization) above.

</details>

---

## ðŸŽ® Usage

### Scenario A: Taking an Intentional Break
1. When you step away from your desk, do either:
   - **Double-click** the **Study Break** desktop shortcut, OR
   - Press **`Ctrl + Alt + B`** on your keyboard.
2. A popup confirms: *"Study Break Activated! Auto-shutdown is PAUSED."*
3. Your PC stays ON normally with no forced sleep. After 30 minutes of idle time, the background watcher sees your break signal and skips shutdown.
4. When you come back, just **start typing or moving the mouse** â€” NightWatch
   *auto-clears* your break signal as soon as it notices activity
   (typically within ~1 minute). You can also click the button again to
   manually toggle it off.

### Scenario B: Accidentally Falling Asleep
1. You fall asleep while studying without hitting the break button.
2. After **30 minutes of no mouse/keyboard activity**, the background watcher runs.
3. It detects that no intentional break signal exists.
4. It performs a clean, forced shutdown to protect your battery and hardware.

---

## âš™ï¸ Customization

Want to change the idle duration (e.g. to 20 or 45 minutes)?

The 30-minute idle threshold is set in `IdleMistakeDetector.ps1`:

```powershell
$targetIdleSeconds = 1800   # 30 minutes
```

1. Open `IdleMistakeDetector.ps1` in any text editor (Notepad, VS Code, etc.).
2. Change `1800` to your preferred value in seconds:
   - `1200` = 20 minutes
   - `2700` = 45 minutes
   - `3600` = 1 hour
3. Save the file.
4. Re-run `Reinstall.bat` so the new script gets picked up by the scheduled task.

> **Why not the Task Scheduler GUI?** NightWatch uses a 1-minute `TimeTrigger` (not the
> "On idle" trigger), so the *Conditions* tab in `taskschd.msc` does not control the
> actual threshold â€” editing the script does.

---

## â“ Frequently Asked Questions

#### Q: Do I need to double-click the shortcut?
**A:** Yes, like standard Windows desktop shortcuts, it opens with a double-click. **Pro Tip:** You can also press **`Ctrl + Alt + B`** from anywhere, or right-click the shortcut and select **Pin to Taskbar** for a single-click button!

#### Q: Why Hibernate instead of Sleep?
**A:** Standard Sleep continues drawing battery to keep RAM active (wasting 15%â€“30% overnight and keeping the laptop warm in a backpack). Hibernate dumps RAM state directly to your SSD and drops power consumption to **absolute zero**.

#### Q: Will this close my unsaved files if I fall asleep?
**A:** If you fall asleep without hitting the break button, it executes `shutdown /s /f /t 0` to preserve the hardware. We strongly recommend using browser session restore (Chrome/Edge $\rightarrow$ *"Continue where you left off"*) and Auto-Save in your text editors (VS Code, Word, etc.).

---

## ðŸ—‘ï¸ Uninstallation

To cleanly remove the shortcut and scheduled task:
1. Open **PowerShell as Administrator**.
2. Located to your **Repository Folder**.
3. Run:
```powershell
.\Uninstall-StudySafetySystem.ps1
```

---

## ðŸ“„ License
 
Distributed under the **[Apache License 2.0](LICENSE)**. Includes patent grants, contributor terms, and trademark protection. Free for personal and commercial use.
