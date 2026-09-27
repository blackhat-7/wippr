# Wispr Flow Android onboarding (v2.5.2, build 166)

**TL;DR (2026-09-27)**
- Android Flow is **not a keyboard**. It uses an AccessibilityService to insert text, a floating "Flow Bubble" overlay, and a foreground mic service. Onboarding asks for overlay, accessibility, mic, battery "No restrictions" and notifications.
- **The PiP guide is real picture-in-picture.** `AccessibilitySettingsPipActivity` enters PiP, then opens Accessibility Settings. A muted, looping 7.8 s screen recording (510×768) of the exact Settings taps, with a yellow tap-highlight circle, floats over Settings. It closes itself once the toggle is on.
- **They pull the user back automatically:** a background service polls every 1 s and relaunches the app the moment a permission flips.
- The user **tries dictation in-app before any system Settings trip**: a mock bubble, then "reps" dictating into fake Gmail, Notes and WhatsApp cards. Mic permission is asked in context there.
- A progress bar, checkpoints to resume where the user left off, an exit confirmation, and a plain-language privacy/legal screen before the scary permission.

Source: decompiled APK (jadx + apktool) of the Wispr Flow Android APK (v2.5.2). Key files: `com/wispr/ui/onboarding/order/*StepOrder`, `flowapp/activity/AccessibilitySettingsPipActivity.java`, `flowapp/service/OnboardingService.java`, `res/raw/vid_pip_access_perm.mp4`.

## Step order (A/B "tiy_ptt_revamp")
1. Value props → "How it works" → "What is Flow".
2. **Try it yourself** tutorial (mic permission asked here): "Say something!", "Tap once you're done", "Nice, that worked!".
3. **Value reps**: dictate into fake email / notes cards and watch them get formatted ("Well done, Flow formats your text").
4. "You're all set" → language → showreel ("works in over 100,000 apps").
5. Overlay permission → accessibility legal notice → accessibility permission (in-app mock Settings cards with numbered steps, then the PiP video) → privacy choice → battery → notifications → attribution → done.

## PiP details worth copying
- PiP aspect 85:128. Auto-enter, and re-enter PiP on expand, Back or leave-hint.
- 700 ms fallback: open Settings even if the PiP callback never fires. If PiP is unsupported, open Settings directly.
- Completion is detected by a ContentObserver on the settings value plus a re-check in onResume, and then the guide finishes itself.
- The video is a real device recording, muted, looping, with a highlighted tap target.

## What this means for noboard on iOS
- **PiP works on iOS too:** `AVPictureInPictureController` with `canStartPictureInPictureAutomaticallyFromInline = true`, playing a looping muted guide video. The app already has the `audio` background mode, which covers PiP.
- **iOS can't pull the user back** the way Android does: there is no API to leave Settings. So the guide video ends on the "‹ noboard" back link, and the app re-checks when it becomes active.
- **Shorter path:** `UIApplication.openSettingsURLString` opens noboard's own Settings page, which for an app with a keyboard extension has **Keyboards → noboard** and **Allow Full Access** in one place. One trip covers both steps (verify on device).
- **Detecting completion:** "keyboard added" can be checked on app activation (e.g. the keyboard writes a heartbeat to the App Group once it has been shown, and Full Access is known because the keyboard can write at all). Verify which signals work on iOS 27.
- Copy the **try-it-before-Settings** ordering: let the user feel dictation in-app first. On iOS that needs the keyboard, so use a mock in-app strip that records through the app directly.
