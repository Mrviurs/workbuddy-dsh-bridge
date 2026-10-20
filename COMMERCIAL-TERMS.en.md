# Commercial License Terms (Template)

> **This is a template, not an executed agreement.** Fill in every `[ ]` placeholder.
>
> **How to use it**: copy → fill → send for confirmation → **written acceptance is enough**
> (email, an issue reply, or an explicit chat message, as long as it is on record) → keep a copy each.
>
> Minimum for the license to take effect: ① you (licensor) agree in writing; ② the licensee
> explicitly accepts these terms; ③ scope, term, and fee each have a concrete value.
>
> This is not legal advice. If the fee is significant or the licensee is a public company, have a
> lawyer review it.

---

## 0. Negotiation summary (read this first)

One line: **you may use it, here `___`, for this long `___`, for this fee `___`, and these things
are off the table.**

| Item | Typical answer |
|---|---|
| Scope | Internal tool / Embedded in a product / Delivered with a project |
| Term | 12 months, renewable |
| Fee | Free (attribution only) / one-off `___` / `___` per year |
| Hard red lines | No reselling someone else's service, no public relay API, no harvesting credentials |

---

## 1. Parties

| | |
|---|---|
| **Licensor** | lynx ("Licensor") |
| **Licensee** | `[Full legal name]`, registered in `[ ]`, company no. `[ ]` |
| **Licensee contact** | `[Name / email]` |
| **Effective date** | `[YYYY-MM-DD]` |

---

## 2. Scope of license

**2.1 Permitted use** (tick one or more; anything unticked is not licensed)

- [ ] **A. Internal tool** — used by Licensee's employees on their work devices, not offered to third parties
- [ ] **B. Product integration** — embedded in `[product name]`, distributed as `[commercial / internal deployment]`
- [ ] **C. Client delivery** — delivered to Licensee's clients as part of `[project/service type]`
- [ ] **D. Other** — `[describe]`

**2.2 Licensed entity**
Licensee only. **Excludes** affiliates, subsidiaries, and contractors unless listed here:
`[additional entities]`

**2.3 Scale cap**
`[ ]` devices / `[ ]` concurrent users / `[ ]` deployments

**2.4 Territory**
`[Worldwide]` / `[Limited to ___]`

**2.5 Version scope**
Covers `v1.x`. Future major versions: `[included]` / `[not included — requires written confirmation]`

---

## 3. Term and renewal

| Item | Terms |
|---|---|
| Term | `[12]` months from the effective date |
| Renewal | `[Confirmed in writing 30 days before expiry; otherwise it lapses]` |
| After expiry | No new deployments; existing deployments `[may run for up to 90 days]` / `[must be retired within 30 days]` |

---

## 4. Fees

- **4.1 License fee**: `[amount]` `[currency]`, `[one-off / annual]`
- **4.2 Payment**: `[ ]`, net `[ ]` days
- **4.3 Late payment**: licence suspends automatically `[30]` days after due date
- **4.4 Taxes**: each party bears its own
- **4.5 Free-of-charge case**: if granted free, state "this section does not apply; Licensee only owes the attribution duty in §5.1"

---

## 5. Licensee obligations

**5.1 Attribution**
Include the following in the product's About / Credits / Open-source notices page, or in the
accompanying documentation:

> This product uses workbuddy-dsh-bridge (author: lynx, https://github.com/Mrviurs/workbuddy-dsh-bridge)

**5.2 Keep notices**
Do not remove, obscure, or alter the `LICENSE`, copyright notice, or author attribution in the source.

**5.3 Mark modifications**
If you modify the source, mark it ("based on workbuddy-dsh-bridge") in the changed code or changelog,
and do not imply endorsement by the original author.

**5.4 Usage report**
Every `[12]` months, send a short report (deployment count, primary use, issues encountered). For
project statistics and improvement only; no trade secrets involved.

**5.5 Compliance duty**
Licensee is **solely responsible** for ensuring its use complies with the terms of upstream services
(WorkBuddy / CodeBuddy, DeepSeek) and with applicable laws. Licensor makes no compliance
representation.

---

## 6. Uses never permitted (even under this license)

The following violate §4 of the project [LICENSE](../LICENSE), and **this license grants no rights
for them whatsoever**:

1. Extracting, collecting, reselling, topping up, pooling, proxying, or redistributing **another
   person's** account credentials, access tokens, or model quota;
2. Circumventing, reducing, or avoiding fees owed to any third-party product or service;
3. Mass registration, multi-account pooling, or credential-harvesting services;
4. Any unlawful purpose, or use violating upstream terms of service;
5. Redistributing after removing copyright or license notices;
6. Claiming the Software is officially certified, endorsed by, or affiliated with the author or any
   upstream vendor.

**Any breach of this section terminates the license immediately, with no refund.**

---

## 7. No warranty and limitation of liability

**7.1 No warranty**
The Software is provided "AS IS", without any express or implied warranty, including merchantability,
fitness for a particular purpose, and non-infringement. Licensor does not warrant that it is
available, uninterrupted, error-free, or will not damage data.

**7.2 Liability cap**
To the maximum extent permitted by law, Licensor's total aggregate liability arising from this license
or the Software shall not exceed **`[fees actually paid]`** (or, for a free license, RMB 100).

**7.3 Exclusion of indirect loss**
Licensor is not liable for indirect, incidental, special, consequential, or punitive damages, including
lost profits, lost data, leaked credentials, account standing, lost quota, or lost goodwill.

---

## 8. Indemnity

Licensee shall indemnify, defend, and hold Licensor harmless from:

1. third-party claims arising from Licensee's use of the Software;
2. any claim by an upstream service provider or account holder relating to Licensee's use;
3. Licensee's breach of these terms or of the [LICENSE](../LICENSE).

---

## 9. Termination

| Event | Consequence |
|---|---|
| Either party gives `[30]` days' written notice | Terminates at expiry; prepaid fees refunded pro rata for unused months (if applicable) |
| Licensee breaches §5.2, §5.3, or §6 | **Immediate termination**, no refund |
| Licensee's payment overdue by `[30]` days | License suspended; restored on payment |

On termination, Licensee must stop using and destroy all copies; **instances already delivered to its
clients** are handled per the "after expiry" rule in §3.

---

## 10. Miscellaneous

- **10.1** These terms plus the [LICENSE](../LICENSE) are the entire agreement regarding the Software.
- **10.2** If any provision is unenforceable, the rest remains in force.
- **10.3** Governing law: `[ ]`; disputes: `[negotiation, then arbitration by ___]` / `[courts of ___]`.
- **10.4** These terms are not legal advice.

---

## Signatures

| | Licensor | Licensee |
|---|---|---|
| Signed by | lynx | `[name]` |
| Title | Author / copyright holder | `[title]` |
| Date | `[ ]` | `[ ]` |
| Signature / seal | | |

> Electronic acceptance is valid: an email saying "we accept the terms above", or an explicit issue
> reply, is sufficient evidence. Screenshot it and keep it on file.

---

## Appendix: reply template for commercial enquiries

> If the enquiry arrives on GitHub, just point them at the **Commercial License Request**
> issue form - it already asks for these three things:
> <https://github.com/Mrviurs/workbuddy-dsh-bridge/issues/new/choose>

> Thanks for your interest in workbuddy-dsh-bridge.
>
> The project is free for personal use; commercial use needs a short written license. Template here:
> https://github.com/Mrviurs/workbuddy-dsh-bridge/blob/main/COMMERCIAL-TERMS.md
>
> Could you reply with three things so I can fill it in and send it back?
>
> 1. Full company name and country of registration
> 2. How you intend to use it (internal tool / product integration / delivered to clients)
> 3. Rough scale (headcount or deployment count)
>
> On fees: `[free, attribution in your credits page is enough]` / `[___ per year, covering ___
> deployments]`.
>
> Two red lines up front: it cannot be used to resell or top up someone else's account service, and it
> cannot be run as a public relay API. Those are not licensable at any price, because they involve
> upstream terms of service that are outside what I can authorise.

---

## Appendix: author's pre-signature checklist

- [ ] Scope ticked; scale given as a number (not "some" or "a few")
- [ ] Term and post-expiry handling stated
- [ ] Fee, or "free + attribution", stated explicitly
- [ ] Liability cap filled in (leaving it blank means uncapped)
- [ ] The six red lines in §6 are intact — the counterparty didn't delete them
- [ ] Attribution location named specifically (which page / which file)
- [ ] Both parties confirmed in writing, and it is archived
