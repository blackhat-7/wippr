# Wispr Flow — what it does, and how the iPhone app really works

Researched 2026-09-26. Main sources: Wispr's own help center (docs.wisprflow.ai, articles updated Sept 2026), their blog and changelog, Baseten's case study, r/WisprFlow and r/iphone threads (read through the Reddit JSON API), and X posts checked one by one through api.fxtwitter.com.

## TL;DR

- **Everything runs in the cloud. Nothing runs on the device.** Audio streams to Baseten by gRPC. A fine-tuned Llama does the cleanup. The target is under 700 ms end to end at p99. There is no offline mode (as of 2026-09). In Aug 2026 they previewed their own ASR model, "Canto".
- **iOS app = keyboard extension + main app that holds the mic.** A keyboard extension can't record. So tapping the mic jumps you to the Flow app, which starts a "Flow session" (background audio, with a Live Activity in the Dynamic Island), then jumps back ("switchback"). The keyboard then just sends mic on/off to the main app. **Text lands in another app only if the Flow keyboard is up.** Otherwise it goes to the clipboard.
- **The session stays open with the mic live.** It auto-stops after 5 min idle by default. Options: Immediately / 5 min / 15 min / 1 h / Never. One dictation is capped at 5 min on iOS (20 min on desktop).
- **iPhone is clearly the weak platform.** Users complain about the app bounce, the swipe-back (iOS 26.4 broke auto-return), the half-built keyboard they have to switch away from to type, the orange mic dot and Dynamic Island that won't go away, battery drain, and stuck Action Button runs. Wispr's own staff tell iPhone users to use the Action Button or switch to Android.
- **For wippr:** Wispr already ships Action Button, Control Center, Back Tap and Siri triggers that record in the background, with a Live Activity showing Stop and a timer. So "no keyboard" capture is solved. **Inserting text into another app without a keyboard is not solved.** Wispr falls back to the clipboard. That is wippr's real problem.

---

## 1. Core features (all platforms)

From [wisprflow.ai/features](https://wisprflow.ai/features) and the help center:

| Feature | What it does | iOS? |
|---|---|---|
| Dictation, 100+ languages | Detects one language per dictation. Supports Hinglish, a Swiss-German spelling variant and code-switching ([languages](https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages)) | yes. iOS has an Auto-detect option |
| Auto cleanup | Removes filler words, handles self-corrections ("2… actually 3" becomes 3), turns spoken numbers into lists, adds punctuation from pauses and tone. Levels: None / **Light (default)** / Medium, where Medium rewrites for concision ([auto-cleanup](https://docs.wisprflow.ai/articles/4283510616-auto-cleanup-control-how-much-flow-edits-your-dictation-beta)) | Level picker is Mac/Windows only |
| Styles | Formal / Casual / very casual / Excited!, set per app category (Personal msg, Work msg, Email, Other). English only ([styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles)) | yes. After iOS 26.4 there is one style per category plus a "Quick Style Switcher" pill on the keyboard |
| Context awareness | Reads text near the cursor and on screen, the app or website, and names such as email recipients. It sorts the app into a category, matches casing and spacing, and spells names correctly. On desktop the context can include **a screenshot** and conversation history ([context](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness)) | "iOS (limited to the focused text field)", meaning the keyboard's `textDocumentProxy` |
| Dictionary | Custom words, plus "Correct a misspelling" rules. Also learns words on its own ([dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)) | yes |
| Snippets | A spoken trigger expands to saved text ([snippets](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets)) | yes |
| Command Mode | Hold a hotkey and speak an edit or instruction. Paid plans only ([command mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode)) | **"On iOS … in-place text editing is not currently working"**. Only web-search commands work |
| Whisper mode | Recognizes whispered speech. No toggle; you keep the mic close ([features](https://wisprflow.ai/features)) | yes, as a model capability |
| Notes / Scratchpad | Voice notes. Lock Screen and Control Center widgets ([notes](https://docs.wisprflow.ai/articles/3529886556-using-notes-in-wispr-flow-for-ios)) | yes, iOS 18.3+ |
| Notetaker | Meeting notes, launched Aug 2026 | desktop first |

Their main metric is the **"zero-edit rate"**: the share of dictations the user sends without changing anything. Word error rate is secondary. At launch they claimed 50–70% zero-edit, against under 5% for Apple and Google dictation ([Show HN, 2024-09](https://news.ycombinator.com/item?id=41696153)).

## 2. The iOS app in detail

App Store facts (2026-09-26): v1.76, iOS 18.3+, 185.9 MB, 4.8★ from 16k+ ratings ([App Store](https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487)). Launched 2025-06-03 ([launch tweet](https://x.com/WisprFlow/status/1929953749784768633), [TechCrunch](https://techcrunch.com/2025/06/03/wispr-flow-releases-ios-app-in-a-bid-to-make-dictation-feel-effortless/)).

### 2.1 Architecture: the keyboard can't record, so the main app does

- The keyboard extension needs **Full Access**, for network and for talking to the app group. Microphone permission must be requested by the **main app**: "Keyboard extensions can't show iOS permission dialogs, so the prompt has to come from the main app" ([keyboard setup](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone)).
- "**Dictation runs in the main Flow app even when started from the keyboard**" ([orange-dot article](https://docs.wisprflow.ai/articles/3634682593-why-the-orange-dot-or-mic-indicator-stays-on-after-dictating-ios)).
- The keyboard is a thin remote control plus the place text gets inserted. The main app records in the background and streams to the cloud. The finished text goes back to the keyboard, which inserts it. "[The transcript] pastes only when the Flow keyboard is active; otherwise … notification" ([missing-chunks article](https://docs.wisprflow.ai/articles/9620169737-ios-missing-audio-chunks-during-unstable-internet)).
- On iPhone, Flow **mixes with other audio instead of interrupting it**. Music keeps playing and can leak into the transcript. There is no ducking option on iOS. "Flow can also keep recording while backgrounded or with the screen locked" ([background audio](https://docs.wisprflow.ai/articles/8415579688-why-wispr-flow-doesn-t-pause-background-audio-on-iphone-ios)).

### 2.2 Step by step (keyboard path)

1. Open any app's text field. Long-press the globe key and pick Wispr Flow. You have to do this every time unless Flow is already your active keyboard.
2. If no session is running, the mic button becomes **Start** (or "Start Flow"). Tapping it opens the Flow app.
3. The Flow app starts audio and the session, and starts a **Live Activity** (a Dynamic Island pill, "Wispr Flow / on").
4. **Switchback:**
   - *Auto:* Flow reopens the app you came from. This needs Flow to identify that app and the app to support being reopened. The first time, you confirm a prompt. v1.63 (2026-06-24) added "native switchback" for Claude, ChatGPT, Gemini, Perplexity, LinkedIn and others ([changelog](https://wisprflow.ai/whats-new), [r/WisprFlow update](https://www.reddit.com/r/WisprFlow/comments/1ulytvl/july_2_2026_product_updates_android_reliability/)).
   - *Manual:* a "Flow is on — Swipe right across the bottom edge to continue" screen. iOS 26.4 (Mar 2026) broke automatic return, so users had to swipe themselves ([Adapting to iOS 26.4](https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4)).
   - The handoff "expires shortly after you leave the keyboard". If the switch doesn't complete, it clears after 10 s.
   - After you swipe back, Flow auto-starts a dictation within a short window.
5. Speak. Tap ✓ (keep the text) or ✕ (discard). The text is inserted at the cursor after processing, **not word by word**.
6. Later dictations in the same session start instantly from the keyboard mic, with no bounce, until the session ends.

### 2.3 Session lifetime

From the [orange-dot article](https://docs.wisprflow.ai/articles/3634682593-why-the-orange-dot-or-mic-indicator-stays-on-after-dictating-ios):

- Setting: **"Disable Flow after"**, with Never / 1 hour / 15 min / **5 min (default)** / Immediately. The countdown runs only while the session is idle, Flow is in the background and the keyboard is inactive. It never cuts off an active dictation.
- The same setting decides whether the session resumes after an audio interruption such as a call.
- **Each dictation is capped at 5 min on iOS.** At the cap Flow stops and processes. Desktop allows 20 min ([20-min article](https://docs.wisprflow.ai/articles/4841123325-longer-dictation-sessions-now-up-to-20-minutes)). Android has its own limits.
- If iOS reports low memory, Flow cancels and **throws away the audio**.
- Calls, Siri, and plugging or unplugging a headset or Bluetooth device all stop recording.
- Network drop in the middle of a dictation: Flow keeps a local copy of the audio and re-transcribes when it can. Nothing is inserted until that finishes. Failed dictations can be retried from History.

### 2.4 Triggers that don't need the keyboard

From the [shortcuts article](https://docs.wisprflow.ai/articles/1986921789-how-to-set-up-flow-shortcuts-for-iphone) and the [Action Button article](https://docs.wisprflow.ai/articles/4500510662-set-up-the-action-button-for-flow-on-iphone):

- **App Intents** (Siri and Shortcuts): *Dictate a Flow Note*, *Quick Dictation to Clipboard*, *Quick Dictation to Notes*, *Turn On/Off Flow*, *Open Flow Notes*, *Create a Flow Note*. "Dictate a Flow Note, Quick Dictation to Clipboard, Quick Dictation to Notes, Turn On/Off Flow, and the Control Center recording toggle **run in the background**." Only Open Flow Notes brings the app to the foreground.
- **Action Button** (iPhone 15 Pro and later): press and hold to start, press and hold again to stop. While it runs, the Dynamic Island shows "Hold to stop" and a timer. **The Live Activity must be enabled or the Action Button path breaks**: one user who turned off Live Activities got "quit unexpectedly" crashes ([r/WisprFlow](https://www.reddit.com/r/WisprFlow/comments/1vwf5dm/my_iphone_apparently_decided_that_im_using_the/)). This fits Apple's `AudioRecordingIntent` rule that a background-recording intent must show a Live Activity (my inference, not stated by Wispr).
- **Control Center:** a recording toggle and a "Flow Notes" button. **Lock Screen:** a circular Flow Notes widget. **Back Tap**, through a Shortcut.
- **Dynamic Island / Live Activity:** shows a timer, plus **Stop** and **Notes** buttons during normal dictation, or **Save note** during note capture. Since v1.62 (2026-06-10) the timer shows for every dictation.
- **Where the text goes:** if the Flow keyboard is active, into the focused field. Otherwise it is returned as a Shortcut result and copied to the **clipboard** (Quick Dictation to Clipboard), or saved as a Flow note. So without the keyboard the flow is: Action Button → speak → press again → switch to the target app → **paste by hand**.

### 2.5 Wispr's keyboard itself

- It is only a partial keyboard: mic, punctuation, a 123 layout, and an "ABC" layout added in 2026. The system keyboard takes over for number, phone, email and decimal fields, and for apps that block third-party keyboards (banking apps).
- They once had a full letter keyboard and **removed it**: "it wasn't as smooth as Apple's for text editing. Things like long-pressing to move the cursor vertically or using certain gestures are restricted by iOS" (u/VictoriaAtWispr, 2025-10-20, [thread](https://www.reddit.com/r/WisprFlow/comments/1o9ma6m/feature_request_make_the_mobile_wispr_flow/)). As of Aug 2026 they are "redesigning the iOS experience" ([thread](https://www.reddit.com/r/WisprFlow/comments/1vz0fnk/love_wispr_flow_on_mac_hate_it_on_iphone_what_am/)).
- On Android they use a **floating bubble** that works over any app, with no keyboard switching. Wispr staff openly say Android is the better experience ([comment](https://www.reddit.com/r/WisprFlow/comments/1qnwiqk/using_whiprflow_ios_driving_me_nuts/)).

## 3. Cloud vs on-device, latency, stack

- **Cloud only.** "Transcription always occurs on the cloud" ([Data Controls](https://wisprflow.ai/data-controls), updated 2026-08-18). No offline mode. In June 2026, asked about offline dictation, Wispr answered "This is something we want to add soon!" ([thread](https://www.reddit.com/r/WisprFlow/comments/1u9jjhj/june_18_2026_product_updates_reliability_privacy/)). The iOS keyboard shows "No Network" and won't dictate without a connection.
- **Latency budget** (CTO Sahaj Garg, [Technical challenges](https://wisprflow.ai/post/technical-challenges), 2025-09-11): under 700 ms from end of speech to formatted text. That splits into **ASR under 200 ms + LLM under 200 ms + network under 200 ms**. At the time they handled 1B words a month. Personalization data mostly stays on the device.
- **LLM:** fine-tuned **Llama** on **Baseten**, using TensorRT-LLM on AWS. "100+ tokens in <250 ms", p99 under 700 ms ([Baseten case study](https://www.baseten.co/resources/customers/wispr-flow/)).
- **ASR:** until mid-2026 the model wasn't disclosed; audio is streamed live over gRPC to a Baseten endpoint. An independent teardown of the macOS app found audio streamed to `model-…grpc.api.baseten.co` together with the app, the URL, accessibility-tree text, and proper nouns pulled out by a separate LLM call (`/llm/extract_asr_words`). It measured model inference at ~210 ms ([wensenwu.com, 2026-04-04](https://wensenwu.com/thoughts/wispr-flow-investigation); one person's teardown). **Canto**, their first in-house ASR model, was previewed 2026-08-17. They claim it takes noisy-condition WER from 30%+ down to 5–10% and cuts dictations needing edits by 30–35% ([Tanay Kothari's X article](https://x.com/tankots/status/2089431610865471641)).
- **Latency tricks:** stream audio while the user is still speaking, so transcription is mostly done at release. Extract names and context in parallel. Skip cleanup for very short or very long text ([auto-cleanup](https://docs.wisprflow.ai/articles/4283510616-auto-cleanup-control-how-much-flow-edits-your-dictation-beta)). Skip context reading if it can't finish quickly ([context](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness)). Other providers named by third-party reviewers (OpenAI, Anthropic, Cerebras) are **(unverified)**.
- **Scale and money:** $280M Series B at a $2B valuation, Aug 2026 ([same X article](https://x.com/tankots/status/2089431610865471641)). Before that, $30M Series A (Menlo). Earlier the $26M total was reported by [TechCrunch](https://techcrunch.com/2025/06/03/wispr-flow-releases-ios-app-in-a-bid-to-make-dictation-feel-effortless/).

## 4. Pricing (2026-09-26)

- **Basic (free):** 2,000 words a week on desktop. **1,000 words a week on iPhone, hard stop at 1,500** ([keyboard setup](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone)).
- **Pro:** $15/mo or $143.99/yr. Weekly plan $4.49. Student plan $7.49/mo ([App Store IAPs](https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487)). 14-day trial. Team, Growth and Enterprise plans on top.

## 5. Privacy controversies

- **2025 screenshots and banned user.** Early builds sent screenshots of the active window for context. A user who raised this was banned, and the community Slack was shut down. The CTO later apologized. He said the screenshot feature "used screenshots (with explicit permission during onboarding)… never stored data, and we removed the screenshot feature before our ProductHunt launch" (u/SahajAtWispr, [2025-09-22](https://www.reddit.com/r/WisprFlow/comments/1n9b8az/security_privacy_and_performance_whats_changed_in/)). Wispr's own post blamed "a scrappy contractor". I could not find the original ban thread; it is described second-hand ([ModelPiper](https://modelpiper.com/blog/wispr-flow-privacy-incident)).
- **Still true in 2026:** the desktop context-awareness docs list "a screenshot" among the things that can accompany a dictation ([context](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness)). The Apr 2026 macOS teardown found a system-wide `CGEventTap` keystroke tap, 1,688 app/URL events logged over 30 h, raw audio stored locally, and PostHog, Sentry, Segment and Datadog telemetry ([wensenwu.com](https://wensenwu.com/thoughts/wispr-flow-investigation)).
- **Defaults:** "Improve the model for everyone" is **ON by default for Free and Pro** and off for Enterprise ([data settings](https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow)). Dictation Cloud Storage is on by default ([Data Controls](https://wisprflow.ai/data-controls)). SOC 2 Type II, HIPAA BAA, and ISO 27001 (announced).
- **iOS scare, 2026-04:** a user saw "other people's dictation" appear. Wispr said the model hallucinated on empty or poor audio ([thread](https://www.reddit.com/r/WisprFlow/comments/1t011dl/major_security_issue_i_can_see_other_peoples/)). This shows cloud ASR can invent coherent text from silence.

## 6. What iPhone users say

### Reddit — complaints (mostly r/WisprFlow)

- "On Mac I press a button, dictate. It transcribes. Done. On iPhone I have to swipe. It keeps listening after I finish dictating … I'm constantly switching between keyboards. This sort of gets rid of any efficiency gain" — u/cktokm99, 2026-08-26, 36 pts ([link](https://www.reddit.com/r/WisprFlow/comments/1vz0fnk/love_wispr_flow_on_mac_hate_it_on_iphone_what_am/))
- "If they spent some time building a keyboard that didn't suck, it would be great. There'd never be a reason to swipe out" — u/Low_Raccoon_784 ([link](https://www.reddit.com/r/WisprFlow/comments/1vz0fnk/love_wispr_flow_on_mac_hate_it_on_iphone_what_am/p61ra0g/))
- "The transcription on iOS is actually fine, and the auto-switching back seems to have improved. However, the keyboard itself lets the whole product down. It's unusable." — u/bluenikes, 2026-08-14 ([link](https://www.reddit.com/r/WisprFlow/comments/1vko57u/has_wispr_on_ios_improved_in_the_last_6_months/p3ly29u/))
- "Every time you tap the dictation button, it redirects you to the app so you can activate it before you start speaking. If you leave it inactive for a while, you have to activate it again. That defeats the whole purpose of having a third-party keyboard" — r/iphone, 2026-08-06 ([link](https://www.reddit.com/r/iphone/comments/1vh3xqu/do_you_agree_that_apple_needs_to_stop_crippling/))
- On the Dynamic Island: "I've stopped using it on iPhone due to this and the fact you can't use Siri when it's active" — u/simonkeane, 2026-06-28 ([link](https://www.reddit.com/r/WisprFlow/comments/1uhr0ao/wispr_flow_is_hogging_dynamic_island_on_my_iphone/oudzauz/))
- Battery: "my iPad or my iPhone can go from 100% charge to 50% in less than two hours with Wispr" — 2026-04-03 ([link](https://www.reddit.com/r/WisprFlow/comments/1sbhf4m/battery_drain/)). Another user says the open session stopped the screen from auto-locking ([link](https://www.reddit.com/r/WisprFlow/comments/1olrpf6/does_keeping_wispr_flow_always_on_drain_battery_a/nn10qfu/)).
- Action Button: "when it works it's just amazing … But then it will get stuck sometime, and I either have to press it 2 or 3 times … or I sometimes have to kill the app entirely" — u/HelloThisIsFlo, 2026-08-26 ([link](https://www.reddit.com/r/WisprFlow/comments/1vyqltv/iphone_action_button_user_experience/p62it49/))
- Text doesn't reach the field: "Iphone ver keep acting in a way where it doesn't put my dictation in text boxes so I have to keep copying/pasting" — u/kimsj756 ([link](https://www.reddit.com/r/WisprFlow/comments/1vz0fnk/love_wispr_flow_on_mac_hate_it_on_iphone_what_am/p65dmeq/))
- iOS 26.4 beta broke the keyboard entirely for some users ("cannot switch to the keyboard to start flow") — 2026-02-16 ([link](https://www.reddit.com/r/WisprFlow/comments/1r6j77h/ios_264_beta_1_breaks_wisprflow/))
- Cloud quality and outages: "the March outage hit me during a deadline and I had zero fallback because the app is cloud-only" — 2026-06-08, 64 pts ([link](https://www.reddit.com/r/WisprFlow/comments/1u0egnx/longtime_user_honestly_the_quality_has_been_going/))

### Reddit — praise

- The Action Button plus Shortcut workaround is the most-liked iPhone setup: "this was the first time it felt immediately essential" — u/senorbiloba, 2025-11-30 ([link](https://www.reddit.com/r/WisprFlow/comments/1pa48h1/ios_shortcut_on_action_button_brilliant/))
- "I have a shortcut set up that I use double tapping the back of my phone for and it has made using Wispr flow 1 million times better" — u/FlyingDutchLady, 2026-07-07 ([link](https://www.reddit.com/r/WisprFlow/comments/1qnwiqk/using_whiprflow_ios_driving_me_nuts/ovzwomw/))
- Accuracy and cleanup are widely praised. The complaints are about the **delivery on iOS, not the transcription quality**.
- Competitors users mention: Willow (full keyboard, offline), Superwhisper, Spokenly, Aqua Voice, Typeless, and native iOS 27 dictation ("much better" but "still far behind").

### X (Twitter)

X search needs a login, and the xcancel/nitter mirrors are down (451 or no response). So I found posts through web search and checked each one with `api.fxtwitter.com`. Every quote below was checked that way.

- "you changed my life! … the accuracy is unreal … **your iOS keyboard experience is dogshit.** please put me in contact with whoever is in charge of it" — @YouKnowEno, 2026-07-31 ([link](https://x.com/YouKnowEno/status/2083123965485367454))
- "They definitely got my vote! Moreover **it would actually make Wispr Flow usable on the iPhone.**" (quoting a post saying Apple should buy Wispr) — @ivanburazin, 2026-03-08 ([link](https://x.com/ivanburazin/status/2030736871312290138))
- "is there anyway to trigger dictation on an iPad when I'm using the Magic Keyboard. When there is no on screen keyboard you can't switch on screen keyboards" — @evielync, 2025-09-10 ([link](https://x.com/evielync/status/1965599465093652793))
- Praise: "It removes your 'ums' and 'ahs'. If stop to correct yourself, it uses the corrected version. It can detect if something should be formatted as a bulleted or numbered list" — @MichaelHyatt, 2025-08-23 ([link](https://x.com/MichaelHyatt/status/1959298182711791815)). Note: this post contains a referral link.
- A post by @iamitp saying "iOS and iPad OS is a pain" showed up in search results but returns NOT_FOUND (probably deleted), so it is not quoted.

## 7. Implications for wippr

**Hard iOS constraints that Wispr's design exposes:**

1. **A keyboard extension can't record audio.** Only the main app can, running as a background-audio session. Every competitor ends up with an app bounce or a session that stays alive.
2. **Background recording started from an intent needs a Live Activity.** Wispr's Action Button and Control Center paths depend on it. Turning Live Activities off breaks them. Likely `AudioRecordingIntent` (iOS 18+), to be confirmed in `ios-platform-constraints.md`. **This is exactly the Dynamic Island mechanism wippr wants, and it clearly ships and works.**
3. **Only a keyboard can insert text into another app** (`textDocumentProxy`). Even Wispr, with $300M+ raised, falls back to the **clipboard** when its keyboard isn't up. Island capture alone ends in a manual paste. This is the central question for `ios-platform-constraints.md`.
4. Auto-returning to the previous app is fragile. iOS 26.4 broke it, and Wispr now keeps an allow-list of apps it can reopen. Don't design around jumping between apps.
5. A long-lived mic session costs battery, keeps the orange dot on, blocks Siri, and can stop auto-lock. Dictations get killed by calls, route changes and low memory.

**Copy:**
- A Live Activity with a timer and Stop / Cancel buttons, started from the Action Button, Control Center, Back Tap or a Siri intent that records in the background.
- Cleanup presets. Filler removal plus self-correction plus lists should be the default ("Light"). Skip the LLM for very short text.
- Save the audio locally first. Transcripts are recoverable from history and can be retried. Send a notification when a dictation is interrupted.
- Personal dictionary, and correction rules for words that keep coming out wrong.
- A "zero-edit rate" metric for our own evals.

**Avoid:**
- Making the keyboard the main surface, or a half-built keyboard users have to switch away from.
- Depending on the cloud. On-device is a real selling point against the outages, "taking longer than usual", privacy worries and hallucinations on silence. Handle silence explicitly (voice-activity detection or an energy gate before ASR).
- A mic session that never ends. Stop audio as soon as the dictation finishes unless the user opts in to keeping it live.
- Mixing background music into the recording (Wispr doesn't duck audio on iOS). Consider ducking.

**Open question for the build:** clipboard plus an automatic paste prompt, or a minimal "insert-only" keyboard that stays hidden until needed? See `ios-platform-constraints.md`.
