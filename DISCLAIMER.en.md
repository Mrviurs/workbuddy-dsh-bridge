# Disclaimer & Acceptable Use

> **Last updated: 2026-10-20**
> This document is a precondition for using this project. Downloading, running, modifying,
> or otherwise using this project constitutes acceptance of everything below.
> This is not legal advice. If real legal consequences are at stake, consult a lawyer in your jurisdiction.

---

## 1. Not affiliated with anyone

This project (`workbuddy-dsh-bridge`, "the Software") is an **independent personal project**.

- It is **not** an official product, plugin, SDK, or partnership of Tencent / WorkBuddy / CodeBuddy.
- It is **not** an official integration of DeepSeek / DeepSeek Harness.
- It has **no** authorization, endorsement, sponsorship, or support from any of the companies above.
- The author has **no relationship** (employment, agency, partnership, or otherwise) with them.

All trademarks and product names belong to their respective owners. Names appear here only to
describe *what the Software talks to* — nothing more.

---

## 2. What the Software actually does (read this properly)

To leave no room for "I assumed it did nothing", here is the literal behaviour:

| # | Behaviour | Detail |
|---|---|---|
| 1 | **Reads memory of a local process** | Extracts the access token (a ~30-day JWT) from the WorkBuddy process **you** started |
| 2 | **Writes the credential to a local file** | Plain text at `C:\temp\wb-jwt.txt` |
| 3 | **Starts a local service** | Launches the `codebuddy --serve` binary shipped inside your WorkBuddy install, bound to `127.0.0.1` |
| 4 | **Forwards your conversation** | Your prompts, system prompt, and tool calls go through that local service to `www.workbuddy.cn` — the **same data path** as using WorkBuddy directly |
| 5 | **Registers autostart entries** | Creates two Windows Task Scheduler tasks: `WorkBuddyCleanServe` and `WorkBuddyRelay` |

**The Software collects, reports, and uploads nothing.** No telemetry, no analytics, no remote
config, no update pings. Audit the source offline to verify.

---

## 3. Risks you accept by using it

### 3.1 Account and service risk

- The Software reuses **your own** account quota and permissions. Upstream may treat the resulting
  traffic as atypical client behaviour.
- Possible consequences (**the author cannot intervene and accepts no responsibility**):
  - rate limiting (HTTP 429), throttling, suspension, or account ban;
  - unexpected credit consumption or billing anomalies;
  - risk-control challenges or extra verification;
  - a finding that you breached the provider's terms of service.
- **Whether to use it, and whether to keep using it, is your decision and your risk.**

### 3.2 It will break eventually

The Software depends on **undocumented internal interfaces** of the WorkBuddy client
(`/api/v1/runs`, ACP, CLI flags, environment variable names). None of these are stable public APIs.

- Upstream may change or remove them in **any** update;
- When that happens the Software stops working, and **the author has no obligation to fix it**;
- **No availability commitment** is made, and no feature is guaranteed to keep working.

### 3.3 Credential exposure

- The token at `C:\temp\wb-jwt.txt` is **roughly equivalent to your account password**.
- If you commit it, paste it in a chat, upload it to cloud storage, or let others use your machine,
  **that is on you**.
- Never include anything matching `eyJ...` in issues, PRs, or screenshots.

### 3.4 Configuration and file risk

- The Software modifies your DSH config (`cordis.patch.yml`, `.credentials.yaml`) and registers
  scheduled tasks.
- The author is **not liable** for data loss, broken settings, or unusable projects resulting from
  those modifications.
- Read section 7 of the [Idiot-Proof Guide](docs/GUIDE.md) before uninstalling.

---

## 4. Prohibited uses

Beyond the noncommercial restriction in [LICENSE](LICENSE), the following are **expressly forbidden**:

| Prohibited | Why |
|---|---|
| **Commercial use** (internal business workflows, paid services, commercial product integration) | See LICENSE §3. Obtain written permission first |
| **Reselling, renting, reselling access, or charging for access** | You would be reselling someone else's service, not this Software |
| **Running it as a relay/proxy offering an API to others** | Directly violates upstream terms and shifts risk onto the author |
| **Mass account registration, account pooling, extracting other people's credentials** | Abuse of the upstream service; not this project's purpose |
| **Helping others bypass official payment or licensing** | Unrelated to this project and potentially unlawful |
| **Redistributing after removing copyright or license notices** | Violates LICENSE §3(a) and §3(g) |
| **Any unlawful purpose, or any use violating upstream terms of service** | Liability rests with the person acting, not the tool |

If your scenario requires any of the above, **this project is not for you**.

---

## 5. Warranty and liability (summary)

Full text: [LICENSE](LICENSE) §5–§7. In short:

- Provided **"AS IS"**, with no express or implied warranty (merchantability, fitness for a
  particular purpose, non-infringement included);
- The author **does not guarantee** it runs, stays uninterrupted, is error-free, or preserves your data;
- The author is **not liable** for indirect, incidental, special, consequential, or punitive damages,
  including lost profits, lost data, leaked credentials, account standing, or lost quota;
- **You agree to indemnify the author** against third-party claims arising from your use.

---

## 6. Your compliance obligations

You are responsible for verifying and complying with:

1. the WorkBuddy / CodeBuddy terms of service;
2. the DeepSeek / DeepSeek Harness terms of use;
3. the **laws and regulations** of your jurisdiction regarding software use, account sharing,
   reverse engineering, and data processing;
4. your employer's IT and information-security policies, if applicable.

**The author cannot and will not make that judgement for you.** The moment you click "Start",
you have made it yourself.

---

## 7. Licensing status, stated precisely

- This project uses the **[Noncommercial Source-Available License v1.0](LICENSE)**:
  source is readable, modifiable, and free for personal use — **commercial use is prohibited**.
- Strictly speaking it is therefore **not OSI open source** (the OSI definition requires allowing
  commercial use). The accurate term is **source-available**.
- If you want a more legally mature noncommercial text, consider
  [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/).
  If you want true open source (commercial use allowed), switch to MIT / Apache-2.0 — but that
  contradicts "no commercial use". The trade-off is yours to make.

---

## 8. Changes

This disclaimer may be updated as the project evolves. Updates appear in git history
(commits touching `DISCLAIMER*.md`); no separate notice is given. Continued use means acceptance.

---

**One line: this is a tool for one person using their own computer. If something goes wrong, it's your problem, not anyone else's.**
