// UFI CPU调节器 WebUI 逻辑
import { exec } from './kernelsu.js';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
const cstatusEl = $('cstatus');
const gov0El = $('gov0'), gov4El = $('gov4'), gov7El = $('gov7');

const fmt = (name) => {
    const map = { schedutil: 'SchedUtil 智能', uscfreq: 'USCFreq', performance: 'Performance 高性能', conservative: 'Conservative 平衡', powersave: 'Powersave 省电' };
    return map[name] || (name || '读取中…');
};

// dump 输出解析: POLICY=x / GOV=... / ON=i:v
function parseDump(output) {
    const policies = {};
    let i = -1;
    for (const raw of (output || '').split('\n')) {
        const t = raw.replace(/\r$/, '').trim();
        if (!t) continue;
        if (/^CTX=(.*)$/.test(t)) {
            policies.ctx = t.slice(4);
        } else if (/^POLICY=\d+$/.test(t)) {
            i = t.slice('POLICY='.length);
            policies[i] = {};
        } else if (i >= 0 && /^GOV=/.test(t)) {
            policies[i].gov = t.slice('GOV='.length);
        } else if (/^ON=\d:\d$/.test(t)) {
            const m = t.slice(3).split(':');
            policies['on' + m[0]] = m[1];
        }
    }
    return policies;
}

const ctl = (args) => exec(`sh /data/adb/modules/ufi_cpu_adjust/ctl.sh ${args}`);

async function refresh() {
    const { errno, stdout } = await ctl('dump');
    if (errno !== 0) {
        gov0El.textContent = gov4El.textContent = gov7El.textContent = '读取失败';
        statusEl.textContent = 'ctl.sh dump 失败 (errno=' + errno + ')';
        return;
    }
    const p = parseDump(stdout);
    if (p.ctx) statusEl.textContent = 'ctl 运行于 ' + p.ctx;
    gov0El.textContent = fmt(p[0] && p[0].gov);
    gov4El.textContent = fmt(p[4] && p[4].gov);
    gov7El.textContent = fmt(p[7] && p[7].gov);
    document.querySelectorAll('.btns button[data-gov]').forEach(b => b.classList.remove('active'));
    const cur = p[0] && p[0].gov;
    const active = document.querySelector(`.btns button[data-gov="${cur}"]`);
    if (active) active.classList.add('active');
    renderCores(p);
}

function renderCores(p) {
    const mk = (i) => {
        const row = document.createElement('div');
        row.className = 'switch';
        const label = document.createElement('span');
        label.textContent = 'CPU' + i;
        const on = document.createElement('button');
        on.className = 'on';
        on.setAttribute('aria-label', 'CPU' + i);
        on.classList.toggle('active', p['on' + i] === '1');
        row.appendChild(label);
        row.appendChild(on);
        on.onclick = async () => {
            const target = on.classList.contains('active') ? 0 : 1;
            const { errno, stdout } = await ctl(`core ${i} ${target}`);
            if (errno === 0 && /^OK /.test((stdout || '').trim())) {
                on.classList.toggle('active', target === 1);
                cstatusEl.textContent = `CPU${i} 已${target ? '开启' : '关闭'}`;
            } else {
                cstatusEl.textContent = `CPU${i} ${target ? '开启' : '关闭'}失败` + (stdout || '');
            }
            await refresh();
        };
        return row;
    };
    const group0 = $('cores0'), group4 = $('cores4');
    group0.innerHTML = '';
    group4.innerHTML = '';
    for (let i = 0; i < 4; i++) group0.appendChild(mk(i));
    for (let i = 4; i < 8; i++) group4.appendChild(mk(i));
}

$('btn_onall').onclick = async () => {
    const { errno, stdout } = await ctl('on_all');
    cstatusEl.textContent = (errno === 0 && /^OK /.test((stdout || '').trim())) ? '全部核心已开启' : ('失败 ' + (stdout || ''));
    await refresh();
};

document.querySelectorAll('.btns button[data-gov]').forEach(btn => {
    btn.onclick = async () => {
        const g = btn.getAttribute('data-gov');
        statusEl.textContent = '应用 ' + fmt(g) + ' …';
        const { errno, stdout, stderr } = await ctl(`gov ${g}`);
        if (errno === 0 && /^OK /.test((stdout || '').trim())) {
            statusEl.textContent = '已应用并保存 ' + fmt(g);
            await refresh();
        } else {
            statusEl.textContent = '应用失败 ' + (stdout || stderr || '');
        }
    };
});

refresh().catch(e => {
    statusEl.textContent = '初始化错误: ' + e;
});