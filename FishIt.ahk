; ============================================================================
;  Fish It - perfect cast + prompt-driven reeling
;  AutoHotkey v1
;
;  F1  calibrate the CAST pixel     (charge bar, at the perfect point)
;  F2  calibrate the REEL pixel     (the red STOP button)
;  F8  start / pause
;  F9  reset stats
;  ESC exit
;
;  Settings are saved to FishIt.ini next to this script, so calibration
;  survives a restart. Delete the ini to start over.
; ============================================================================

#NoEnv
#SingleInstance Force
SetBatchLines, -1
CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
SetMouseDelay, -1

global INI := A_ScriptDir . "\FishIt.ini"

; ---------------------------------------------------------------- settings --
global castX, castY, castColor, castTol
global reelX, reelY, reelColor, reelTol

; how long to hold the charge before we even start looking for the perfect
; colour. stops a stray leftover click registering as a cast.
global minHoldMs      := 150
global maxHoldMs      := 5000    ; give up on the charge bar after this
global promptWaitMs   := 10000   ; how long to wait for Click Fast! to appear
global maxReelMs      := 20000   ; hard stop on a reel
global goneFrames     := 5       ; consecutive misses before "prompt over"
global cooldownMs     := 900     ; pause between cycles

; humanised click timing during the reel
global clickMinMs     := 85
global clickMaxMs     := 145

; ------------------------------------------------------------------ state --
global isRunning := false
global cycles := 0, catches := 0, fails := 0, streak := 0
global startTime := 0, pauseStart := 0
global lbDown := false
global monitorOn := false
global castAX, castAY, reelAX, reelAY, monIdx := "?" 

LoadSettings()
BuildGui()
return


; ============================================================================
;  calibration
; ============================================================================

F1::
    ; sample IMMEDIATELY - no dialog, because clicking a dialog moves the cursor
    MouseGetPos, mx, my
    PixelGetColor, mc, %mx%, %my%, RGB
    MonOffset(ox, oy)
    castX := mx - ox, castY := my - oy, castColor := mc
    SaveSettings()
    Status("CAST set: mon" . monIdx . " rel " . castX . "," . castY)
return

F2::
    MouseGetPos, mx, my
    PixelGetColor, mc, %mx%, %my%, RGB
    MonOffset(ox, oy)
    reelX := mx - ox, reelY := my - oy, reelColor := mc
    SaveSettings()
    Status("REEL set: mon" . monIdx . " rel " . reelX . "," . reelY)
return

F3::
    monitorOn := !monitorOn
    if (monitorOn) {
        SetTimer, Monitor, 100
        Status("Monitor ON")
    } else {
        SetTimer, Monitor, Off
        Status("Monitor OFF")
        GuiControl,, vMonCast, -
        GuiControl,, vMonReel, -
    }
return

Monitor:
    Resolve()
    if (castX != "") {
        PixelGetColor, c1, %castAX%, %castAY%, RGB
        d1 := Round(ColorDiff(c1, castColor))
        m1 := (d1 <= castTol) ? "MATCH" : "no"
        GuiControl,, vMonCast, % Hex(c1) . "  diff " . d1 . "  (tol " . castTol . ")  " . m1
    }
    if (reelX != "") {
        PixelGetColor, c2, %reelAX%, %reelAY%, RGB
        d2 := Round(ColorDiff(c2, reelColor))
        m2 := (d2 <= reelTol) ? "MATCH" : "no"
        GuiControl,, vMonReel, % Hex(c2) . "  diff " . d2 . "  (tol " . reelTol . ")  " . m2
    }
return

; live tolerance tuning
F6::
    castTol := castTol + 3
    SaveSettings()
    Status("castTol = " . castTol)
return
+F6::
    castTol := (castTol > 3) ? castTol - 3 : 0
    SaveSettings()
    Status("castTol = " . castTol)
return
F7::
    reelTol := reelTol + 5
    SaveSettings()
    Status("reelTol = " . reelTol)
return
+F7::
    reelTol := (reelTol > 5) ? reelTol - 5 : 0
    SaveSettings()
    Status("reelTol = " . reelTol)
return


; ============================================================================
;  controls
; ============================================================================

F8::
    if (castX = "" || reelX = "") {
        MsgBox, 48, Not calibrated, Press F1 to set the cast pixel and F2 to set the reel pixel first.
        return
    }
    isRunning := !isRunning
    if (isRunning) {
        if (startTime = 0)
            startTime := A_TickCount
        else
            startTime += A_TickCount - pauseStart
        GuiControl,, vState, RUNNING
        GuiControl, +cGreen, vState
        SetTimer, Tick, 500
        SetTimer, MainLoop, -10
    } else {
        pauseStart := A_TickCount
        SetTimer, MainLoop, Off
        ReleaseMouse()
        GuiControl,, vState, PAUSED
        GuiControl, +cOrange, vState
        Status("Paused")
    }
return

F9::
    if (isRunning) {
        MsgBox, 48, Busy, Pause first.
        return
    }
    cycles := 0, catches := 0, fails := 0, streak := 0
    startTime := 0, pauseStart := 0
    UpdateStats()
    Status("Stats reset")
return

Esc::
    isRunning := false
    SetTimer, MainLoop, Off
    SetTimer, Tick, Off
    ReleaseMouse()
    ExitApp


; ============================================================================
;  main loop - one full cycle per pass
; ============================================================================

MainLoop:
    if (!isRunning)
        return

    Resolve()

    cycles++
    UpdateStats()

    ; ---- 0. make sure the charge pixel is CLEAR before we start ---------
    ; if it already matches, the release fires the instant minHoldMs passes
    ; and you get an instant cast. wait for it to go away first.
    Status("Waiting for charge to clear...")
    t0 := A_TickCount
    clear := false
    while (isRunning && A_TickCount - t0 < 2500) {
        PixelGetColor, pc, %castAX%, %castAY%, RGB
        if (ColorDiff(pc, castColor) > castTol) {
            clear := true
            break
        }
        Sleep, 20
    }

    if (!isRunning)
        return

    if (!clear) {
        fails++, streak++
        UpdateStats()
        Status("Charge pixel stuck ON - recalibrate F1")
        Sleep, %cooldownMs%
        SetTimer, MainLoop, -10
        return
    }

    ; ---- 1. charge and release at the perfect point --------------------
    Status("Casting...")
    SendInput {LButton down}
    lbDown := true
    holdStart := A_TickCount
    perfect := false

    Loop {
        if (!isRunning) {
            ReleaseMouse()
            return
        }
        held := A_TickCount - holdStart
        if (held >= maxHoldMs)
            break
        if (held < minHoldMs) {
            Sleep, 5
            continue
        }
        PixelGetColor, pc, %castAX%, %castAY%, RGB
        if (ColorDiff(pc, castColor) <= castTol) {
            perfect := true
            break
        }
        Sleep, 6
    }

    heldFor := A_TickCount - holdStart
    ReleaseMouse()
    Sleep, 40

    if (perfect)
        Status("Cast held " . heldFor . "ms")

    if (!perfect) {
        fails++, streak++
        UpdateStats()
        Status("Charge never hit target")
        Sleep, %cooldownMs%
        SetTimer, MainLoop, -10
        return
    }

    ; ---- 2. wait for the prompt to clear, then appear -------------------
    ; clearing first stops the previous prompt's leftover pixels from
    ; being read as a fresh one.
    Status("Waiting for prompt...")
    t0 := A_TickCount
    while (isRunning && A_TickCount - t0 < 3000) {
        PixelGetColor, tc, %reelAX%, %reelAY%, RGB
        if (ColorDiff(tc, reelColor) > reelTol)
            break
        Sleep, 10
    }

    t0 := A_TickCount
    found := false
    while (isRunning && A_TickCount - t0 < promptWaitMs) {
        PixelGetColor, tc, %reelAX%, %reelAY%, RGB
        if (ColorDiff(tc, reelColor) <= reelTol) {
            ; confirm across a few frames so one stray pixel can't trigger it
            ok := 0
            Loop, 5 {
                PixelGetColor, vc, %reelAX%, %reelAY%, RGB
                if (ColorDiff(vc, reelColor) <= reelTol)
                    ok++
                Sleep, 3
            }
            if (ok >= 4) {
                found := true
                break
            }
        }
        Sleep, 10
    }

    if (!isRunning) {
        ReleaseMouse()
        return
    }

    if (!found) {
        fails++, streak++
        UpdateStats()
        Status("No prompt")
        Sleep, %cooldownMs%
        SetTimer, MainLoop, -10
        return
    }

    ; ---- 3. click while the prompt is up, stop the instant it clears ----
    Status("Reeling...")
    reelStart := A_TickCount
    lastClick := 0
    clicks := 0
    gone := 0
    caught := false

    while (isRunning && A_TickCount - reelStart < maxReelMs) {
        PixelGetColor, tc, %reelAX%, %reelAY%, RGB
        if (ColorDiff(tc, reelColor) <= reelTol) {
            gone := 0
        } else {
            gone++
            if (gone >= goneFrames) {
                caught := true
                break
            }
            Sleep, 8
            continue
        }

        Random, gap, %clickMinMs%, %clickMaxMs%
        if (A_TickCount - lastClick >= gap) {
            Random, dur, 10, 20
            SendInput {LButton down}
            Sleep, %dur%
            SendInput {LButton up}
            lastClick := A_TickCount
            clicks++

            ; occasional tiny hesitation, roughly once every 30 clicks
            Random, r, 1, 100
            if (r <= 3 && clicks > 12) {
                Random, mp, 70, 140
                Sleep, %mp%
            }
        }
        Sleep, 8
    }

    if (caught) {
        catches++, streak := 0
        Status("Caught - hold " . heldFor . "ms, " . clicks . " clicks")
    } else {
        fails++, streak++
        Status("Reel timeout")
    }
    UpdateStats()

    ReleaseMouse()
    Sleep, %cooldownMs%

    if (isRunning)
        SetTimer, MainLoop, -10
return


; ============================================================================
;  helpers
; ============================================================================

; --- which monitor is the game on, and where is its top-left corner? ---
MonOffset(ByRef ox, ByRef oy) {
    global monIdx
    cx := "", cy := ""
    WinGetPos, wx, wy, ww, wh, ahk_exe RobloxPlayerBeta.exe
    if (ww != "" and ww > 0) {
        cx := wx + ww // 2
        cy := wy + wh // 2
    } else {
        MouseGetPos, cx, cy
    }
    SysGet, cnt, MonitorCount
    Loop % cnt {
        SysGet, m, Monitor, %A_Index%
        if (cx >= mLeft and cx < mRight and cy >= mTop and cy < mBottom) {
            ox := mLeft, oy := mTop, monIdx := A_Index
            return
        }
    }
    ox := 0, oy := 0, monIdx := "?"
}

; turn the stored monitor-relative coords into absolute screen coords
Resolve() {
    global
    MonOffset(ox, oy)
    castAX := castX + ox, castAY := castY + oy
    reelAX := reelX + ox, reelAY := reelY + oy
    GuiControl,, vvMon, % "monitor " . monIdx . "  offset " . ox . "," . oy
}

ReleaseMouse() {
    global lbDown
    if (lbDown) {
        SendInput {LButton up}
        lbDown := false
    }
    Sleep, 20
}

; straight-line distance in RGB space. 0 = identical.
ColorDiff(c1, c2) {
    r := ((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)
    g := ((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)
    b := (c1 & 0xFF) - (c2 & 0xFF)
    return Sqrt(r*r + g*g + b*b)
}

Hex(n) {
    return "0x" . Format("{:06X}", n)
}

LoadSettings() {
    global
    IniRead, castX,     %INI%, Cast, X, %A_Space%
    IniRead, castY,     %INI%, Cast, Y, %A_Space%
    IniRead, castColor, %INI%, Cast, Color, 0x69E142
    IniRead, castTol,   %INI%, Cast, Tol, 12
    IniRead, reelX,     %INI%, Reel, X, %A_Space%
    IniRead, reelY,     %INI%, Reel, Y, %A_Space%
    IniRead, reelColor, %INI%, Reel, Color, 0xCB3F4A
    IniRead, reelTol,   %INI%, Reel, Tol, 40
    castColor += 0
    reelColor += 0
}

SaveSettings() {
    global
    IniWrite, %castX%,     %INI%, Cast, X
    IniWrite, %castY%,     %INI%, Cast, Y
    IniWrite, %castColor%, %INI%, Cast, Color
    IniWrite, %castTol%,   %INI%, Cast, Tol
    IniWrite, %reelX%,     %INI%, Reel, X
    IniWrite, %reelY%,     %INI%, Reel, Y
    IniWrite, %reelColor%, %INI%, Reel, Color
    IniWrite, %reelTol%,   %INI%, Reel, Tol
}

Status(txt) {
    GuiControl,, vAction, %txt%
}

UpdateStats() {
    global
    GuiControl,, vStats, Cycles %cycles%  |  Caught %catches%  |  Failed %fails%
    GuiControl,, vStreak, Fail streak: %streak%
}

Tick:
    if (startTime = 0)
        return
    s := (A_TickCount - startTime) // 1000
    h := s // 3600
    m := Mod(s, 3600) // 60
    sec := Mod(s, 60)
    t := Format("{:02}:{:02}:{:02}", h, m, sec)
    GuiControl,, vTime, %t%
return

BuildGui() {
    global
    Gui, Font, s10 Bold
    Gui, Add, Text, x10 y8 w280 Center, FISH IT
    Gui, Font, s8 Normal

    Gui, Add, GroupBox, x10 y32 w280 h100, Status
    Gui, Add, Text, x20 y52, State:
    Gui, Add, Text, x90 y52 w190 vvState cRed, STOPPED
    Gui, Add, Text, x20 y70, Runtime:
    Gui, Add, Text, x90 y70 w190 vvTime, 00:00:00
    Gui, Add, Text, x20 y88, Action:
    Gui, Add, Text, x90 y88 w190 vvAction, Idle
    Gui, Add, Text, x20 y106 w255 vvStats, Cycles 0  |  Caught 0  |  Failed 0

    Gui, Add, Text, x20 y124 w255 vvStreak, Fail streak: 0
    Gui, Add, Text, x20 y140 w255 vvMon, monitor -

    Gui, Add, GroupBox, x10 y158 w280 h58, Live monitor (F3)
    Gui, Add, Text, x20 y176, Cast:
    Gui, Add, Text, x60 y176 w220 vvMonCast, -
    Gui, Add, Text, x20 y194, Reel:
    Gui, Add, Text, x60 y194 w220 vvMonReel, -

    Gui, Add, GroupBox, x10 y222 w280 h108, Keys
    Gui, Add, Text, x20 y240 w255, F1 = set CAST pixel (hover, then press)
    Gui, Add, Text, x20 y256 w255, F2 = set REEL pixel (hover, then press)
    Gui, Add, Text, x20 y272 w255, F3 = live monitor on / off
    Gui, Add, Text, x20 y288 w255, F6 / Shift+F6 = cast tolerance +/-
    Gui, Add, Text, x20 y304 w255, F7 / Shift+F7 = reel tolerance +/-
    Gui, Add, Text, x20 y320 w255, F8 = start / pause    F9 = reset    ESC = exit

    Gui, +AlwaysOnTop +ToolWindow
    Gui, Show, w300 h345, FISH IT
}
