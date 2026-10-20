# The Idiot-Proof Guide · WorkBuddy Bridge

> For people who don't want to touch a terminal — you just click things.
> No technical knowledge needed. Takes about 5 minutes.

---

## 0. What this thing actually does

Think of models as coworkers:

- **DeepSeek Harness** (DSH for short) is the office you already work in, with its own built-in coworkers.
- **WorkBuddy** is a second office with a few stronger coworkers in it (DeepSeek-V4-Pro, GLM-5.3, Kimi-K3…).

By default, DSH only knows the people in its own office.

Once this bridge is running, DSH can also call over the coworkers from the WorkBuddy office — and **it feels exactly the same**: same chat box, still able to read files, edit code, run commands. You won't notice a difference.

The bridge itself is tiny. It just sits between the two offices and **translates**. Nothing else.

---

## 1. Before you start: check three things

| # | What to check | How to check |
|---|---|---|
| 1 | **WorkBuddy is installed and logged in** | Open it — you can see a chat box and send a message |
| 2 | **Python is installed** | Usually yes if you've ever installed it. If unsure, just continue — step 2 checks it and tells you |
| 3 | **DSH is installed on this same PC** | The machine you normally use DSH on |

> All three are required. If #2 is missing, the app tells you exactly what to install.

---

## 2. First run: five steps

### Step 1 · Open WorkBuddy and send it any message

Open WorkBuddy → type something like "hi" → send it.

**Why?**
WorkBuddy only hands over your credential while it's actually running. Sending a message wakes it up.

**Leave WorkBuddy open in the background** after this.

---

### Step 2 · Install (once)

> **Note: a freshly cloned repository puts nothing on your desktop.**
> The shortcuts are created by the installer, and the .exe is built on your own
> machine (binaries are not shipped in the repo).

In the project folder, double-click **`一键安装.cmd`**.

It does four things automatically (about 2 minutes, no input needed):

1. checks node / python / WorkBuddy
2. **finds where WorkBuddy is installed on your machine** and writes it into the config
   (this is the step that saves you from editing paths by hand)
3. builds the GUI (skipped if it already exists)
4. creates three desktop shortcuts

When it finishes you will see `=== 安装结束 ===` (setup complete) and the desktop icon appears.

If it stops with an error (e.g. node missing), it tells you exactly what to install — fix that and
double-click `一键安装.cmd` again. Re-running is safe.

---

### Step 3 · Double-click "WorkBuddy中转工具" on your desktop

The icon is a blue square with **WB** in it.

A window appears:

```
┌──────────────────────────────────────────────┐
│  WorkBuddy → DeepSeek Harness                │
│  Let DSH use the models inside WorkBuddy      │
├──────────────────────────────────────────────┤
│  ● Relay service   running · port 8791 · signed in │
│  ● API service     running · port 8787 · hard mode │
│  ● Credential      valid · 27 days left            │
├──────────────────────────────────────────────┤
│  [ Start / Repair ]  [ Stop ]  [ Refresh ]    │
├──────────────────────────────────────────────┤
│  Address for DSH                              │
│  http://127.0.0.1:8787/v1     [Copy] [Open folder] │
├──────────────────────────────────────────────┤
│  Log                            [Quit] [Copy diagnostics] │
│  [OK] cached token is valid …                 │
│  [OK] self-hosted serve ready …               │
└──────────────────────────────────────────────┘
```

**Look at exactly one thing: are all three dots green?**

- 🟢🟢🟢 All green → go to step 4.
- 🔴 Any red dot → click the blue **"Start / Repair"** button and wait 20–40 seconds (it works on its own; the log keeps scrolling).
  - When it stops, look again. Still red? Click **"Copy diagnostics"** in the top-right of the log and send me the text.

> **First double-click seems to do nothing?** Wait 3–5 seconds. The app itself takes a moment to launch.

---

### Step 4 · Open DSH and pick a model

Go back to DSH and open the model dropdown. Look for names that **start with `脑力·`** (it means "brainpower"):

```
脑力·DeepSeek-V4-Pro (WB)
脑力·DeepSeek-V4.1-Flash (WB)
脑力·GLM-5.3 (WB)
脑力·Kimi-K3 (WB)
脑力·MiniMax-M3 (WB)
```

Pick one and chat normally.

**Don't see those names?**

| Situation | What to do |
|---|---|
| No such names in the dropdown at all | **Fully quit and reopen DSH** (config changes need a restart) |
| Still missing after restart | This PC's DSH **isn't wired to the bridge yet**: either click "Copy diagnostics" and send it to me, or add the `config/cordis.patch.example.yml` block to your DSH profile yourself (see [README](../README.md)) |

---

### Step 5 · Just use it

You can now work in DSH as usual. It can:

- ✅ Read files, write code, edit configs
- ✅ Run commands and scripts
- ✅ Call several tools in one turn
- ❌ **Cannot see images** (describe the picture to it in words instead)
- ❌ No "thinking process" (you only get the final answer)

---

## 3. Day-to-day usage

### Every time you boot the PC

```
Boot → double-click the WorkBuddy bridge → check the three dots are green → use DSH
```

You do **not** need to click "Start / Repair" every day. It keeps running on its own.

### When to click "Start / Repair" yourself

| When | Why |
|---|---|
| Any dot is red | Something didn't come up |
| WorkBuddy just updated itself | The update may have restarted things |
| Error mentions "not signed in / 401" | Your credential expired (roughly every 30 days) |
| It worked yesterday, fails today | After a reboot the service may not have started |

After clicking, **do nothing else** — it reconnects whatever needs reconnecting.

### Closing the window ≠ quitting

Clicking `×` **only collapses the window to the taskbar**; the program keeps running.

```
Want it out of the way  → click ×        (click the taskbar button to bring it back)
Want it really stopped  → click "Quit" inside the window
```

> If you can find the blue **WB** icon in the taskbar tray (`^` arrow), right-clicking it
> also gives you Show window / Start-Repair / Stop / Quit.

---

## 4. What everything on screen means

| On screen | Meaning |
|---|---|
| **Relay service** | The half that talks to WorkBuddy. Green = connected |
| **API service** | The half that talks to DSH. Green = connected |
| **Credential** | Days left on your pass. Yellow = expiring, red = expired |
| **Start / Repair** | Click when something's wrong; it fixes the broken parts |
| **Stop** | Pauses the service (DSH chats using WorkBuddy models will drop) |
| **Refresh** | Re-check status now (not needed — it refreshes every 5s) |
| **Address for DSH** | A URL used when wiring up DSH; ignore it normally |
| **Copy diagnostics** | ⭐ Click this when something's wrong and paste it to me |
| **Quit** | Actually closes the program |

---

## 5. Troubleshooting

**Do this first**: click **"Copy diagnostics"** and send me the text.
It identifies more than half of all problems, and **it does not contain your password**.

| What you see | Cause | What to do |
|---|---|---|
| Double-click does nothing | Still launching | Wait 5 s; if still nothing, reboot |
| All three dots red | Services aren't up | Click "Start / Repair", wait for it to finish |
| Third dot red: "no credential" | WorkBuddy closed or not signed in | Open WorkBuddy, send a message, then click "Start / Repair" |
| Log says "needs WorkBuddy running" but it is running | Different WorkBuddy builds use different process names; the old check missed them | Fixed (it now scans every candidate process). If it still fails, run `scripts\wb-doctor.ps1` and send the report |
| Third dot yellow: "2 days left" | Credential expiring soon | Not urgent, but send a message + click Start soon |
| DSH says `Connection error` | Bridge isn't running | Open the app → check dots → click Start |
| DSH says `MISSING_CREDENTIAL` | DSH side isn't configured | Send me diagnostics — this is a config issue |
| DSH reports 429 / rate limited | Account quota used too fast | Wait 5–15 min, or switch to a model without `脑力·` |
| Model answers strangely / refuses to cooperate | WorkBuddy chat history formed a stance | Start a **new conversation** in WorkBuddy, then click "Start / Repair" |
| Window vanished | It's on the taskbar | Click the taskbar button, or find WB under the `^` tray arrow |

---

## 6. Three rules you must know

**① Never share your credential (token)**

The app stores a token at `C:\temp\wb-jwt.txt`. It is **roughly equal to your account password**.
Don't copy it, don't screenshot it, don't upload it anywhere. It expires on its own.

**② This is for your own use only**

It spends **your** account quota. If someone else uses it, they burn your quota.
So: keep the service on your own machine, and don't expose it to the internet.

**③ This PC only**

Moving to another computer requires redoing the setup (see `deploy/NEW-MACHINE.md`).
You can't just copy the folder and double-click.

---

## 7. How to remove it completely

1. Open the app → click **Stop**
2. Click **Quit**
3. Delete the project folder
4. Delete `C:\temp\wb-jwt.txt`, `C:\temp\wb-relay.log`, and similar files
5. Delete the desktop shortcut
6. Open **Task Scheduler** and delete the tasks `WorkBuddyCleanServe` and `WorkBuddyRelay`

If you skip step 6, the service will keep starting on every boot.

---

## One-line summary

> **Double-click → check the three green dots → pick a model with `脑力·` → chat normally.**
> If something breaks, click "Copy diagnostics" and send it to me.

Deeper reading (not for beginners): [README](../README.md) · [Runbook](RUNBOOK.md) · [Architecture](ARCHITECTURE.md) · [New machine checklist](../deploy/NEW-MACHINE.md)
