#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WorkBuddy 中转工具 — 图形前端（给不想碰命令行的人用）

双击运行；三盏状态灯 + 启动/停止/刷新 + 实时日志 + 一键诊断报告。
关窗口不退出，缩到系统托盘（托盘菜单可显示/启动/停止/诊断/退出）。
命令行参数 --diagnose：不开窗口，直接生成诊断报告（供排障/自动化用）。
"""
import json
import logging
import os
import queue
import socket
import subprocess
import sys
import threading
import tkinter as tk
import urllib.request
from datetime import datetime
from tkinter import font as tkfont
from tkinter import messagebox, ttk

UI_LOG = r"C:\temp\wb-ui.log"
try:                                     # 日志文件可能被上一次运行占用，绝不能因此崩掉
    from logging.handlers import RotatingFileHandler
    _h = RotatingFileHandler(UI_LOG, maxBytes=200_000, backupCount=2,
                             encoding="utf-8", delay=True)   # delay=True：首次写入才打开
    _h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logging.getLogger().addHandler(_h)
    logging.getLogger().setLevel(logging.INFO)
except Exception:
    pass
APP_TITLE = "WorkBuddy 中转工具"
FONT_NAME = "Microsoft YaHei UI"
JWT_PATH = r"C:\temp\wb-jwt.txt"
DIAG_DIR = r"C:\temp"


def app_root():
    """定位项目根目录（兼容 exe 与源码两种运行方式，向上最多 6 级）。"""
    starts = []
    if getattr(sys, "frozen", False):
        starts.append(os.path.dirname(os.path.abspath(sys.executable)))
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        starts += [os.path.join(here, ".."), here]
    for s in starts:
        cur = os.path.abspath(s)
        for _ in range(6):
            if os.path.exists(os.path.join(cur, "scripts", "wb-clean-start.ps1")):
                return cur
            parent = os.path.dirname(cur)
            if parent == cur:
                break
            cur = parent
    return os.path.abspath(starts[0]) if starts else "."


ROOT = app_root()
START_PS1 = os.path.join(ROOT, "scripts", "wb-clean-start.ps1")
STOP_PS1 = os.path.join(ROOT, "scripts", "wb-relay-stop.ps1")
LOG_PATH = r"C:\temp\wb-relay.log"


def read_settings():
    serve, relay = 8791, 8787
    p = os.path.join(ROOT, "config", "settings.psd1")
    try:
        txt = open(p, encoding="utf-8-sig").read()
        for line in txt.splitlines():
            if "ServePort" in line and "=" in line:
                serve = int("".join(ch for ch in line.split("=")[1] if ch.isdigit()) or serve)
            if "RelayPort" in line and "=" in line:
                relay = int("".join(ch for ch in line.split("=")[1] if ch.isdigit()) or relay)
    except Exception:
        pass
    return serve, relay


SERVE_PORT, RELAY_PORT = read_settings()


def port_open(port, timeout=0.35):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except Exception:
        return False


def http_get(url, headers=None, timeout=3):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def jwt_info():
    try:
        tok = open(JWT_PATH, encoding="utf-8").read().strip()
        payload = tok.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        payload = payload.replace("-", "+").replace("_", "/")
        import base64
        data = json.loads(base64.b64decode(payload).decode("utf-8"))
        exp = datetime.fromtimestamp(data["exp"])
        left = (exp - datetime.now()).total_seconds() / 86400
        return left > 0, round(left, 1), exp.strftime("%Y-%m-%d %H:%M"), data.get("sub", "")
    except Exception:
        return False, 0, "", ""


def schtasks_status(name):
    try:
        out = subprocess.run(["schtasks", "/query", "/tn", name, "/fo", "LIST"],
                             capture_output=True, timeout=10)
        txt = out.stdout.decode("gbk", "replace")
        for line in txt.splitlines():
            if "Status" in line or "状态" in line:
                return line.split(":", 1)[-1].strip()
    except Exception:
        pass
    return "未知"


def collect_status():
    """返回结构化状态，供界面与诊断报告共用。"""
    st = {"serve": {}, "relay": {}, "token": {}, "tasks": {}}
    # serve
    if port_open(SERVE_PORT):
        st["serve"]["up"] = True
        try:
            a = http_get(f"http://127.0.0.1:{SERVE_PORT}/api/v1/auth/status", {"x-codebuddy-request": "1"})
            st["serve"]["auth"] = bool(a.get("authenticated"))
        except Exception:
            st["serve"]["auth"] = None
    else:
        st["serve"]["up"] = False
    # relay
    if port_open(RELAY_PORT):
        st["relay"]["up"] = True
        try:
            h = http_get(f"http://127.0.0.1:{RELAY_PORT}/health")
            st["relay"].update(base=h.get("base"), model=h.get("model"),
                               systemMode=h.get("systemMode"), mode=h.get("mode"))
        except Exception:
            pass
    else:
        st["relay"]["up"] = False
    # token
    ok, left, exp, sub = jwt_info()
    st["token"].update(ok=ok, left=left, exp=exp, sub=sub)
    # tasks
    st["tasks"]["WorkBuddyCleanServe"] = schtasks_status("WorkBuddyCleanServe")
    st["tasks"]["WorkBuddyRelay"] = schtasks_status("WorkBuddyRelay")
    return st


def build_report(st, log_tail):
    lines = []
    lines.append("=== WorkBuddy 中转 诊断报告 ===")
    lines.append(f"生成时间: {datetime.now():%Y-%m-%d %H:%M:%S}")
    lines.append(f"项目根  : {ROOT}")
    lines.append(f"Python  : {sys.version.split()[0]}  frozen={getattr(sys, 'frozen', False)}")
    lines.append("")
    s = st["serve"]
    if s.get("up"):
        auth = {True: "已登录", False: "未登录", None: "无响应"}[s.get("auth")]
        lines.append(f"[中转服务] 端口 {SERVE_PORT} 运行中 · {auth}")
    else:
        lines.append(f"[中转服务] 端口 {SERVE_PORT} 未运行")
    r = st["relay"]
    if r.get("up"):
        mode = "硬解" if str(SERVE_PORT) in str(r.get("base")) else "旧模式"
        lines.append(f"[接口服务] 端口 {RELAY_PORT} 运行中 · {mode} · 上游 {r.get('base')}")
        lines.append(f"           模型 {r.get('model')} · 提示词模式 {r.get('systemMode')}")
    else:
        lines.append(f"[接口服务] 端口 {RELAY_PORT} 未运行")
    t = st["token"]
    if t.get("ok"):
        lines.append(f"[账号凭据] 有效，剩 {t['left']} 天（{t['exp']} 过期） sub={t['sub']}")
    else:
        lines.append("[账号凭据] 无可用 token（启动时会自动从 WorkBuddy 内存重扫）")
    lines.append(f"[计划任务] WorkBuddyCleanServe={st['tasks']['WorkBuddyCleanServe']}  "
                 f"WorkBuddyRelay={st['tasks']['WorkBuddyRelay']}")
    # DSH 侧
    patch = os.path.join(os.environ.get("DSH_HOME") or os.path.join(os.environ["USERPROFILE"], ".dsh"),
                     "profiles", "desktop", "cordis.patch.yml")
    if os.path.exists(patch):
        txt = open(patch, encoding="utf-8").read()
        import re as _re
        m = _re.search(r"baseURL:\s*(\S+)", txt)
        d = _re.search(r"- id: agent-default-model[\s\S]{0,200}?provider:\s*(\S+)", txt)
        lines.append(f"[DSH 配置] baseURL={m.group(1) if m else '?'}  默认 provider={d.group(1) if d else '?'}")
    lines.append("")
    lines.append("--- 日志尾部 ---")
    lines += log_tail if log_tail else ["(无)"]
    return "\n".join(lines)


class App:
    def __init__(self, root):
        self.root = root
        self.q = queue.Queue()
        self.busy = False
        self.tray = None
        self.tray_ok = False
        self.tray_tip_shown = False

        root.title(APP_TITLE)
        root.geometry("780x640")
        root.minsize(700, 560)
        root.configure(bg="#f5f6f8")
        root.protocol("WM_DELETE_WINDOW", self.minimize_to_taskbar)
        try:                                     # 窗口图标用生成图，避免依赖外部 .ico
            from PIL import ImageTk
            self._win_icon = ImageTk.PhotoImage(self.tray_image())
            root.iconphoto(True, self._win_icon)
        except Exception:
            pass

        f_title = tkfont.Font(family=FONT_NAME, size=15, weight="bold")
        f_sub = tkfont.Font(family=FONT_NAME, size=9)
        f_body = tkfont.Font(family=FONT_NAME, size=10)
        f_state = tkfont.Font(family=FONT_NAME, size=11, weight="bold")
        f_btn = tkfont.Font(family=FONT_NAME, size=11, weight="bold")

        head = tk.Frame(root, bg="#1f2937", height=74)
        head.pack(fill="x")
        head.pack_propagate(False)
        tk.Label(head, text="WorkBuddy → DeepSeek Harness", bg="#1f2937", fg="white",
                 font=f_title).pack(anchor="w", padx=18, pady=(12, 0))
        tk.Label(head, text="让 DSH 用上 WorkBuddy 里的模型（DeepSeek-V4-Pro / GLM-5.3 / Kimi-K3 …）",
                 bg="#1f2937", fg="#9ca3af", font=f_sub).pack(anchor="w", padx=18, pady=(2, 0))

        body = tk.Frame(root, bg="#f5f6f8")
        body.pack(fill="x", padx=16, pady=12)
        self.lamp, self.detail = {}, {}
        rows = [("serve", "中转服务", f"端口 {SERVE_PORT}"),
                ("relay", "接口服务", f"端口 {RELAY_PORT}"),
                ("token", "账号凭据", "有效期")]
        for i, (key, label, hint) in enumerate(rows):
            card = tk.Frame(body, bg="white", highlightbackground="#e5e7eb", highlightthickness=1)
            card.grid(row=i, column=0, sticky="ew", pady=4)
            body.grid_columnconfigure(0, weight=1)
            lamp = tk.Label(card, text="●", fg="#9ca3af", bg="white",
                            font=tkfont.Font(family=FONT_NAME, size=16))
            lamp.pack(side="left", padx=(14, 8), pady=8)
            tk.Label(card, text=label, bg="white", fg="#111827", font=f_state,
                     width=8, anchor="w").pack(side="left")
            det = tk.Label(card, text=f"{hint} · 检查中…", bg="white", fg="#6b7280",
                           font=f_body, anchor="w")
            det.pack(side="left", fill="x", expand=True)
            self.lamp[key], self.detail[key] = lamp, det

        btns = tk.Frame(root, bg="#f5f6f8")
        btns.pack(fill="x", padx=16, pady=(4, 10))
        self.btn_start = tk.Button(btns, text="启动 / 修复", command=self.on_start, font=f_btn,
                                   bg="#2563eb", fg="white", activebackground="#1d4ed8",
                                   activeforeground="white", relief="flat", cursor="hand2", height=2)
        self.btn_start.pack(side="left", fill="x", expand=True, padx=(0, 6))
        self.btn_stop = tk.Button(btns, text="停止", command=self.on_stop, font=f_btn,
                                  bg="#e5e7eb", fg="#111827", activebackground="#d1d5db",
                                  relief="flat", cursor="hand2", height=2)
        self.btn_stop.pack(side="left", fill="x", expand=True, padx=6)
        self.btn_refresh = tk.Button(btns, text="刷新", command=self.refresh_status, font=f_btn,
                                     bg="#e5e7eb", fg="#111827", activebackground="#d1d5db",
                                     relief="flat", cursor="hand2", height=2)
        self.btn_refresh.pack(side="left", fill="x", expand=True, padx=(6, 0))

        addr = tk.Frame(root, bg="white", highlightbackground="#e5e7eb", highlightthickness=1)
        addr.pack(fill="x", padx=16)
        tk.Label(addr, text="DSH 里用的地址", bg="white", fg="#6b7280", font=f_sub).pack(
            anchor="w", padx=12, pady=(8, 0))
        line = tk.Frame(addr, bg="white")
        line.pack(fill="x", padx=12, pady=(2, 10))
        self.addr_var = tk.StringVar(value=f"http://127.0.0.1:{RELAY_PORT}/v1")
        tk.Entry(line, textvariable=self.addr_var, font=tkfont.Font(family="Consolas", size=11),
                 relief="flat", bg="#f9fafb", fg="#111827").pack(side="left", fill="x", expand=True, ipady=4)
        for txt, cmd in (("复制", self.copy_addr), ("打开目录", self.open_dir)):
            tk.Button(line, text=txt, command=cmd, font=f_sub, bg="#f3f4f6",
                      relief="flat", cursor="hand2", padx=10).pack(side="left", padx=(6, 0))

        logf = tk.Frame(root, bg="#f5f6f8")
        logf.pack(fill="both", expand=True, padx=16, pady=(10, 14))
        head_row = tk.Frame(logf, bg="#f5f6f8")
        head_row.pack(fill="x")
        tk.Label(head_row, text="运行日志", bg="#f5f6f8", fg="#6b7280", font=f_sub).pack(side="left")
        tk.Button(head_row, text="退出", command=self.quit_app, font=f_sub,
                  bg="#f3f4f6", relief="flat", cursor="hand2", padx=12).pack(side="right", padx=(6, 0))
        tk.Button(head_row, text="复制诊断报告", command=self.copy_diagnose, font=f_sub,
                  bg="#e5e7eb", relief="flat", cursor="hand2", padx=10).pack(side="right")
        box = tk.Frame(logf, bg="white", highlightbackground="#e5e7eb", highlightthickness=1)
        box.pack(fill="both", expand=True, pady=(2, 0))
        self.log = tk.Text(box, height=10, wrap="word", relief="flat", bg="#0f172a", fg="#e5e7eb",
                           font=tkfont.Font(family="Consolas", size=9), insertbackground="#e5e7eb")
        sb = tk.Scrollbar(box, command=self.log.yview)
        self.log.configure(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self.log.pack(side="left", fill="both", expand=True)
        self.log.configure(state="disabled")

        self.write_log("就绪。点「启动 / 修复」开始；关窗口=最小化到任务栏（不退出），要真退出点右上「退出」。")
        self.f_body = f_body
        self.refresh_status()
        self.root.after(200, self.drain)
        self.root.after(5000, self.auto_refresh)
        self.setup_tray()

    # ---------------- 托盘 ----------------
    def tray_image(self):
        from PIL import Image, ImageDraw
        img = Image.new("RGBA", (64, 64), "#2563eb")
        d = ImageDraw.Draw(img)
        d.rectangle([6, 6, 57, 57], outline="white", width=3)
        d.text((20, 22), "WB", fill="white")
        return img

    def setup_tray(self):
        try:
            import pystray
        except Exception as e:
            self.write_log(f"[WARN] 托盘不可用（{e}），关窗口将直接退出", "warn")
            self.root.protocol("WM_DELETE_WINDOW", self.minimize_to_taskbar)
            return
        try:
            menu = pystray.Menu(
                pystray.MenuItem("显示窗口", lambda: self.ui(self.show_window), default=True),
                pystray.MenuItem("启动 / 修复", lambda: self.ui(self.on_start)),
                pystray.MenuItem("停止", lambda: self.ui(self.on_stop_quiet)),
                pystray.MenuItem("复制诊断报告", lambda: self.ui(self.copy_diagnose)),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("退出", lambda: self.ui(self.quit_app)),
            )
            self.tray = pystray.Icon("wb-bridge", self.tray_image(), APP_TITLE, menu)
            self.tray.run_detached()          # 与 Tk mainloop 共存的标准做法
            import time as _t
            _t.sleep(0.8)
            vis = getattr(self.tray, "visible", None)
            logging.info("tray after run_detached: visible=%s", vis)
            if not vis:                       # 某些环境下 run_detached 不会自动显示，显式置 True
                try:
                    self.tray.visible = True
                    _t.sleep(0.6)
                    vis = getattr(self.tray, "visible", None)
                    logging.info("tray after forced visible: visible=%s", vis)
                except Exception:
                    logging.exception("force visible failed")
            self.tray_ok = bool(vis)
            if self.tray_ok:
                self.write_log("[OK] 托盘已启用（右键托盘图标可操作）", "ok")
            else:
                self.write_log("[WARN] 托盘图标创建失败，改用「缩到任务栏」模式（点任务栏按钮可恢复）", "warn")
                self.root.protocol("WM_DELETE_WINDOW", self.minimize_to_taskbar)
        except Exception as e:
            logging.exception("tray init failed")
            self.write_log(f"[WARN] 托盘初始化失败（{e}），关窗口将直接退出", "warn")
            self.root.protocol("WM_DELETE_WINDOW", self.minimize_to_taskbar)

    def ui(self, fn):
        """从托盘线程切回 Tk 主线程。"""
        try:
            self.root.after(0, fn)
        except Exception:
            pass

    def minimize_to_taskbar(self):
        """托盘不可用时的兜底：最小化到任务栏，进程继续跑。"""
        self.root.iconify()
        if not self.tray_tip_shown:
            self.tray_tip_shown = True
            self.write_log("[OK] 已最小化到任务栏，点任务栏图标可恢复（关窗口不会退出）", "ok")

    def hide_to_tray(self):
        if not self.tray_ok:
            self.minimize_to_taskbar()
            return
        self.root.withdraw()
        if self.tray and not self.tray_tip_shown:
            self.tray_tip_shown = True
            try:
                self.tray.notify("已缩到托盘，双击图标可以再打开", APP_TITLE)
            except Exception:
                pass

    def show_window(self):
        self.root.deiconify()
        self.root.lift()
        try:
            self.root.focus_force()
        except Exception:
            pass

    def quit_app(self):
        try:
            if self.tray:
                self.tray.stop()
        except Exception:
            pass
        self.root.destroy()

    # ---------------- 日志 ----------------
    def write_log(self, text, color=None):
        self.log.configure(state="normal")
        for name, fg in (("ok", "#4ade80"), ("err", "#f87171"), ("warn", "#fbbf24"), ("dim", "#94a3b8")):
            self.log.tag_configure(name, foreground=fg)
        self.log.insert("end", text.rstrip() + "\n", color or "default")
        self.log.see("end")
        self.log.configure(state="disabled")

    def drain(self):
        try:
            while True:
                kind, payload = self.q.get_nowait()
                if kind == "log":
                    color = None
                    if "[OK]" in payload:
                        color = "ok"
                    elif "[FAIL]" in payload or "ERR" in payload:
                        color = "err"
                    elif "[WARN]" in payload:
                        color = "warn"
                    self.write_log(payload, color)
                elif kind == "done":
                    self.set_busy(False)
                    self.refresh_status()
        except queue.Empty:
            pass
        self.root.after(200, self.drain)

    # ---------------- 状态 ----------------
    def set_lamp(self, key, state, text):
        colors = {"ok": "#22c55e", "bad": "#ef4444", "warn": "#f59e0b", "idle": "#9ca3af"}
        self.lamp[key].configure(fg=colors.get(state, "#9ca3af"))
        self.detail[key].configure(
            text=text,
            fg="#111827" if state == "ok" else ("#b91c1c" if state == "bad" else "#6b7280"))

    def refresh_status(self):
        st = collect_status()
        s = st["serve"]
        if s.get("up"):
            if s.get("auth"):
                self.set_lamp("serve", "ok", f"运行中 · 端口 {SERVE_PORT} · 已登录")
            elif s.get("auth") is False:
                self.set_lamp("serve", "bad", f"运行中但未登录 · 端口 {SERVE_PORT}（点启动修复）")
            else:
                self.set_lamp("serve", "warn", f"端口 {SERVE_PORT} 在监听，但没响应")
        else:
            self.set_lamp("serve", "bad", f"未运行 · 端口 {SERVE_PORT}（点「启动 / 修复」）")

        r = st["relay"]
        if r.get("up"):
            mode = "硬解" if str(SERVE_PORT) in str(r.get("base")) else "旧模式"
            self.set_lamp("relay", "ok",
                          f"运行中 · 端口 {RELAY_PORT} · {mode} · 模型 {r.get('model') or '—'}")
        else:
            self.set_lamp("relay", "bad", f"未运行 · 端口 {RELAY_PORT}（点「启动 / 修复」）")

        t = st["token"]
        if t.get("ok"):
            self.set_lamp("token", "warn" if t["left"] < 3 else "ok",
                          f"有效 · 还剩 {t['left']} 天（{t['exp']} 过期）")
        else:
            self.set_lamp("token", "bad", "没有可用凭据（点启动会自动从 WorkBuddy 内存里取）")

    def auto_refresh(self):
        if not self.busy:
            self.refresh_status()
        self.root.after(5000, self.auto_refresh)

    # ---------------- 动作 ----------------
    def set_busy(self, busy):
        self.busy = busy
        state = "disabled" if busy else "normal"
        for b in (self.btn_start, self.btn_stop, self.btn_refresh):
            b.configure(state=state)

    def run_ps1(self, script, label):
        if self.busy:
            return
        if not os.path.exists(script):
            messagebox.showerror(APP_TITLE, f"找不到脚本：\n{script}")
            return
        self.set_busy(True)
        self.write_log(f"— {label} —", "dim")

        def worker():
            try:
                cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script]
                p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, creationflags=0x08000000)
                for raw in p.stdout:
                    line = raw.decode("gbk", "replace").rstrip()
                    if line.strip():
                        self.q.put(("log", line))
                p.wait()
                self.q.put(("log", f"— {label}完成（退出码 {p.returncode}）—"))
            except Exception as e:
                self.q.put(("log", f"[FAIL] {e}"))
            finally:
                self.q.put(("done", None))

        threading.Thread(target=worker, daemon=True).start()

    def on_start(self):
        self.show_window()
        self.run_ps1(START_PS1, "启动 / 修复")

    def on_stop(self):
        if not messagebox.askyesno(APP_TITLE, "要停止中转服务吗？\n\nDSH 里正在用 WorkBuddy 模型的对话会断开。"):
            return
        self.run_ps1(STOP_PS1, "停止")

    def on_stop_quiet(self):
        """托盘菜单里的停止：不弹确认，直接停。"""
        self.run_ps1(STOP_PS1, "停止")

    def copy_addr(self):
        self.root.clipboard_clear()
        self.root.clipboard_append(self.addr_var.get())
        self.write_log("[OK] 地址已复制到剪贴板", "ok")

    def open_dir(self):
        try:
            os.startfile(ROOT)
        except Exception as e:
            messagebox.showerror(APP_TITLE, str(e))

    def log_tail(self, n=30):
        try:
            txt = self.log.get("1.0", "end").strip().splitlines()
            return txt[-n:]
        except Exception:
            return []

    def copy_diagnose(self):
        st = collect_status()
        report = build_report(st, self.log_tail(30))
        try:
            os.makedirs(DIAG_DIR, exist_ok=True)
            path = os.path.join(DIAG_DIR, f"wb-diagnose-{datetime.now():%Y%m%d-%H%M%S}.txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write(report)
        except Exception:
            path = "(保存失败)"
        try:
            self.root.clipboard_clear()
            self.root.clipboard_append(report)
        except Exception:
            pass
        self.write_log(f"[OK] 诊断报告已复制到剪贴板，并存到 {path}", "ok")
        return report


def cli_diagnose():
    """--diagnose：不开窗口，直接出报告。"""
    st = collect_status()
    report = build_report(st, [])
    os.makedirs(DIAG_DIR, exist_ok=True)
    path = os.path.join(DIAG_DIR, f"wb-diagnose-{datetime.now():%Y%m%d-%H%M%S}.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(report)
    print(report)
    print(f"\n(saved to {path})")


def main():
    if "--diagnose" in sys.argv:
        cli_diagnose()
        return
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
