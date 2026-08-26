System.register(["react","@grafana/data"],function(exports){"use strict";var R,P;return{setters:[function(m){R=m},function(m){P=m.PanelPlugin}],execute:function(){

var IMG="/public/plugins/ardmatrix-inventory-hub-panel/img/";

var CSS=`:root{
    --bg:#020918; --blue:#2fb7ff; --cyan:#25d7ff; --hub:#1bcaff;
    --ring:#2bd2ff; --green:#38eb83; --yellow:#ffda2d; --red:#ff4f5c; --purple:#b74cff;
    --line:#087dc7; --cardborder:#0a7fd0;
  }
.ardx *{box-sizing:border-box;margin:0;padding:0}
.ardx{background:
  linear-gradient(90deg,rgba(0,7,22,.88),rgba(0,18,47,.58) 50%,rgba(0,7,22,.88)),
  url('/public/plugins/ardmatrix-inventory-hub-panel/img/datacenter-background.png') center/cover no-repeat!important}
.ardx .stage{position:relative;width:1536px;height:1024px;overflow:hidden;background:var(--bg)}
.ardx /* background photo + gradient wash */
  .stage:before{content:"";position:absolute;inset:0;background:url('/public/plugins/ardmatrix-inventory-hub-panel/img/datacenter-background.png') center/cover;opacity:.50}
.ardx .stage:after{content:"";position:absolute;inset:0;
    background:
      radial-gradient(120% 90% at 50% 42%, rgba(0,40,90,.18), rgba(1,7,20,.72) 78%),
      linear-gradient(90deg, rgba(0,7,22,.78), rgba(0,18,47,.18) 50%, rgba(0,7,22,.78));}
.ardx .stage>*{position:relative;z-index:2}
.ardx /* ---- brand ---- */
  .brand{position:absolute;top:10px;left:50%;transform:translateX(-50%);width:540px;height:108px;
    display:flex;align-items:center;justify-content:center;z-index:6}
.ardx .brand img{width:100%;height:100%;object-fit:cover;object-position:center;filter:drop-shadow(0 0 14px rgba(20,120,255,.35))}
.ardx .tag{position:absolute;top:96px;left:50%;transform:translateX(-50%);font-size:13px;font-weight:600;
    letter-spacing:.14em;color:#bcdcf5;z-index:6}
.ardx .tag b{color:var(--cyan);font-weight:700}
.ardx /* ---- connector layer ---- */
  .wires{position:absolute;inset:0;width:100%;height:100%;z-index:1;pointer-events:none}
.ardx .wire-paths path{stroke-dasharray:18 8;animation:wireFlow 2.2s linear infinite}
.ardx .wire-paths path:nth-child(even){animation-direction:reverse;animation-duration:2.8s}
.ardx .wire-nodes circle{animation:nodePulse 1.8s ease-in-out infinite;transform-box:fill-box;transform-origin:center}
.ardx .wire-nodes circle:nth-child(even){animation-delay:.55s}
.ardx /* ---- main 3-col grid ---- */
  .main{position:absolute;left:34px;right:34px;top:118px;bottom:298px;
    display:grid;grid-template-columns:392px 1fr 392px;gap:0}
.ardx .col{display:grid;grid-template-rows:repeat(3,1fr);gap:28px;align-content:center}
.ardx .col.r{justify-items:end}
.ardx .card{display:flex;align-items:stretch;gap:22px;padding:18px 26px;width:392px;min-height:154px;
    border:1.5px solid var(--cardborder);border-radius:26px;text-decoration:none;color:#eaf6ff;
    background:linear-gradient(120deg, rgba(3,30,66,.94), rgba(1,14,38,.92));
    box-shadow:inset 0 0 34px rgba(0,121,230,.16), 0 0 22px rgba(0,60,140,.25);
    backdrop-filter:blur(2px)}
.ardx .card .ico{flex:0 0 92px;height:92px;align-self:center;border:2px solid #46dbff;border-radius:50%;
    display:grid;place-items:center;
    box-shadow:0 0 18px rgba(8,127,255,.55), inset 0 0 20px rgba(0,128,255,.22)}
.ardx .card .ico svg{width:46px;height:46px;stroke:#d8f6ff;fill:none;stroke-width:2;
    stroke-linecap:round;stroke-linejoin:round}
.ardx .card .body{flex:1;min-width:0;display:flex;flex-direction:column;height:100%;padding:6px 0}
.ardx .num{font-size:44px;font-weight:800;line-height:1;color:#ffffff}
.ardx .lbl{margin-top:8px;font-size:16px;font-weight:600;letter-spacing:.06em;color:#dbeeff}
.ardx .det{margin-top:auto;padding-top:10px;border-top:1px solid rgba(70,150,205,.45);
    font-size:12.5px;color:#c7dcea;white-space:nowrap}
.ardx .det .dot{color:var(--green)}
.ardx .g{color:var(--green);font-weight:700}
.ardx .y{color:var(--yellow);font-weight:700}
.ardx .r{color:var(--red);font-weight:700}
.ardx .c{color:var(--cyan);font-weight:700}
.ardx .sep{color:#3f6e8e;margin:0 6px}
.ardx /* ---- center hub ---- */
  .middle{display:flex;align-items:center;justify-content:center;position:relative}
.ardx .hub-wrap{position:relative;width:360px;height:360px;display:grid;place-items:center}
.ardx .hub-svg{position:absolute;inset:-40px;width:440px;height:440px}
.ardx .ring-cw{transform-origin:220px 220px;stroke-dasharray:22 10;animation:ringCW 18s linear infinite}
.ardx .ring-ccw{transform-origin:220px 220px;stroke-dasharray:8 13;animation:ringCCW 13s linear infinite}
.ardx .ring-pulse{animation:ringPulse 2.6s ease-in-out infinite}
.ardx .hub-core{position:relative;width:300px;height:300px;border-radius:50%;display:grid;place-items:center;text-align:center;
    background:radial-gradient(circle, rgba(3,33,74,.98) 0 46%, rgba(0,74,165,.30) 47%, rgba(2,20,52,.15) 62%);}
.ardx .hubtxt b{display:block;font-size:40px;font-weight:800;color:#eafbff;letter-spacing:.02em}
.ardx .hubtxt strong{display:block;font-size:44px;font-weight:800;color:var(--hub);letter-spacing:.02em;
    text-shadow:0 0 18px rgba(27,202,255,.55)}
.ardx .hubtxt span{display:block;margin-top:10px;font-size:13px;font-weight:600;letter-spacing:.28em;color:#cfeaff}
.ardx .wave{margin-top:12px;width:150px;height:20px;stroke:var(--cyan);fill:none;stroke-width:2;
    filter:drop-shadow(0 0 6px rgba(37,215,255,.7))}
.ardx .wave path{stroke-dasharray:18 7;animation:wireFlow 1.2s linear infinite}
@keyframes wireFlow{to{stroke-dashoffset:-52}}
@keyframes ringCW{to{transform:rotate(360deg)}}
@keyframes ringCCW{to{transform:rotate(-360deg)}}
@keyframes ringPulse{0%,100%{opacity:.5}50%{opacity:1}}
@keyframes nodePulse{0%,100%{opacity:.45;transform:scale(.75)}50%{opacity:1;transform:scale(1.45)}}
@media(prefers-reduced-motion:reduce){.ardx .wire-paths path,.ardx .wire-nodes circle,.ardx .ring-cw,.ardx .ring-ccw,.ardx .ring-pulse,.ardx .wave path{animation:none}}
.ardx .health{position:absolute;bottom:-20px;left:50%;transform:translateX(-50%);width:210px;padding:10px 8px;
    border:1.5px solid #0b8ff0;border-radius:40px;background:rgba(3,22,50,.96);text-align:center;
    box-shadow:0 0 20px rgba(6,120,230,.35)}
.ardx .health small{display:block;font-size:11px;letter-spacing:.14em;color:#bcdcf5;font-weight:600}
.ardx .health small:before{content:"● ";color:var(--green)}
.ardx .health b{display:block;font-size:34px;font-weight:800;color:var(--green);line-height:1.1}
.ardx /* ---- intel strip ---- */
  .intel{position:absolute;left:34px;right:34px;bottom:128px;height:126px;
    display:grid;grid-template-columns:repeat(5,1fr);
    border:1.5px solid var(--line);border-radius:22px;background:rgba(2,20,48,.94);
    box-shadow:inset 0 0 30px rgba(0,90,180,.12), 0 0 22px rgba(0,50,120,.25)}
.ardx .ii{display:flex;align-items:center;justify-content:center;gap:16px;border-right:1px solid rgba(20,90,139,.6);padding:0 8px}
.ardx .ii:last-child{border-right:0}
.ardx .ii .iico{width:60px;height:60px;border:1.5px solid currentColor;border-radius:50%;display:grid;place-items:center;
    box-shadow:0 0 14px currentColor;flex:0 0 60px}
.ardx .ii .iico svg{width:30px;height:30px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.ardx .ii .txt{color:#eaf6ff}
.ardx .ii .t{font-size:12px;font-weight:600;letter-spacing:.06em;color:#d3e7f4}
.ardx .ii .v{font-size:34px;font-weight:800;line-height:1.05;color:#ffffff}
.ardx .ii .s{margin-top:4px;font-size:11px;color:#a9c4d6}
.ardx .ii .s b{font-weight:700}
.ardx /* ---- bottom nav ---- */
  .nav{position:absolute;left:22px;right:22px;bottom:38px;height:76px;
    display:grid;grid-template-columns:repeat(10,1fr);
    border:1.5px solid var(--line);border-radius:18px;background:rgba(2,18,44,.97);
    box-shadow:0 0 22px rgba(0,50,120,.3)}
.ardx .nav a{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;
    border-right:1px solid rgba(20,90,139,.55);color:#cfe6f6;text-decoration:none;
    font-size:10px;font-weight:600;letter-spacing:.04em}
.ardx .nav a:last-child{border-right:0}
.ardx .nav a svg{width:24px;height:24px;stroke:#6fdcff;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.ardx .nav a.active{background:linear-gradient(180deg, rgba(9,110,220,.30), rgba(9,80,190,.10));color:#eafaff}
.ardx .nav a.active svg{stroke:#9fefff}
.ardx .foot{position:absolute;bottom:10px;left:50%;transform:translateX(-50%);font-size:12px;color:#9fbdd2;letter-spacing:.08em}`;
var HTML=`

  <div class="brand"><img src="/public/plugins/ardmatrix-inventory-hub-panel/img/ardmatrix-aiops-transparent-final.png" alt="ARDMATRIX AIOps"></div>
  <div class="tag">Analytics&nbsp; <b>|</b> &nbsp;Results&nbsp; <b>|</b> &nbsp;Decisions</div>

  <!-- radiating connectors -->
  <svg class="wires" viewBox="0 0 1536 1024" preserveAspectRatio="none">
    <defs>
      <linearGradient id="wireL" x1="1" y1="0" x2="0" y2="0">
        <stop offset="0" stop-color="#18a9ff"/><stop offset="1" stop-color="#7b4dff"/>
      </linearGradient>
      <linearGradient id="wireR" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="#18a9ff"/><stop offset="1" stop-color="#7b4dff"/>
      </linearGradient>
      <filter id="wglow" x="-40%" y="-40%" width="180%" height="180%">
        <feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
      </filter>
    </defs>
    <g class="wire-paths" fill="none" stroke-width="3.2" filter="url(#wglow)" stroke-linecap="round">
      <!-- left column -->
      <path d="M636 332 C 560 300, 520 214, 452 210" stroke="url(#wireL)"/>
      <path d="M624 398 C 560 398, 520 394, 452 394" stroke="url(#wireL)"/>
      <path d="M636 464 C 560 496, 520 584, 452 580" stroke="url(#wireL)"/>
      <!-- right column -->
      <path d="M900 332 C 976 300, 1016 214, 1084 210" stroke="url(#wireR)"/>
      <path d="M912 398 C 976 398, 1016 394, 1084 394" stroke="url(#wireR)"/>
      <path d="M900 464 C 976 496, 1016 584, 1084 580" stroke="url(#wireR)"/>
    </g>
    <g class="wire-nodes" fill="#66e0ff">
      <circle cx="452" cy="210" r="5"/><circle cx="452" cy="394" r="5"/><circle cx="452" cy="580" r="5"/>
      <circle cx="1084" cy="210" r="5"/><circle cx="1084" cy="394" r="5"/><circle cx="1084" cy="580" r="5"/>
    </g>
    <g fill="#9d7bff" opacity=".9">
      <circle cx="536" cy="262" r="3.5"/><circle cx="536" cy="536" r="3.5"/>
      <circle cx="1000" cy="262" r="3.5"/><circle cx="1000" cy="536" r="3.5"/>
    </g>
  </svg>

  <div class="main">
    <!-- LEFT COLUMN -->
    <div class="col l">
      <a class="card" href="/d/ardmatrix-inventory-overview/data-center-inventory-overview?orgId=1">
        <div class="ico"><svg viewBox="0 0 24 24">
          <rect x="4" y="3" width="7" height="18" rx="1"/><rect x="13" y="8" width="7" height="13" rx="1"/>
          <line x1="6.5" y1="6.5" x2="8.5" y2="6.5"/><line x1="6.5" y1="10" x2="8.5" y2="10"/><line x1="6.5" y1="13.5" x2="8.5" y2="13.5"/>
          <line x1="15.5" y1="11.5" x2="17.5" y2="11.5"/><line x1="15.5" y1="15" x2="17.5" y2="15"/></svg></div>
        <div class="body"><div class="num">__DC__</div><div class="lbl">DATA CENTERS</div>
          <div class="det"><span class="dot">●</span> <span class="g">All Sites Operational</span></div></div>
      </a>
      <a class="card" href="/d/ardmatrix-rack-inventory/rack-inventory?orgId=1&var-site=All&var-rack=All">
        <div class="ico"><svg viewBox="0 0 24 24">
          <rect x="4" y="3.5" width="16" height="4.2" rx="1"/><rect x="4" y="10" width="16" height="4.2" rx="1"/><rect x="4" y="16.5" width="16" height="4.2" rx="1"/>
          <circle cx="7" cy="5.6" r="0.7" fill="#d8f6ff"/><circle cx="7" cy="12.1" r="0.7" fill="#d8f6ff"/><circle cx="7" cy="18.6" r="0.7" fill="#d8f6ff"/></svg></div>
        <div class="body"><div class="num">__RACK__</div><div class="lbl">RACKS</div>
          <div class="det">Utilization : <span class="c">__RACKU__</span></div></div>
      </a>
      <a class="card" href="/d/ardmatrix-server-inventory/server-inventory?orgId=1&var-site=All&var-rack=All&var-server=All">
        <div class="ico"><svg viewBox="0 0 24 24">
          <rect x="3.5" y="5" width="17" height="5" rx="1"/><rect x="3.5" y="13" width="17" height="5" rx="1"/>
          <circle cx="6.5" cy="7.5" r="0.8" fill="#d8f6ff" stroke="none"/><line x1="9" y1="7.5" x2="16.5" y2="7.5"/>
          <circle cx="6.5" cy="15.5" r="0.8" fill="#d8f6ff" stroke="none"/><line x1="9" y1="15.5" x2="16.5" y2="15.5"/></svg></div>
        <div class="body"><div class="num">__SRV__</div><div class="lbl">PHYSICAL SERVERS</div>
          <div class="det">Healthy : <span class="g">__SRVH__</span><span class="sep">|</span>Warning : <span class="y">__SRVW__</span><span class="sep">|</span>Critical : <span class="r">__SRVC__</span></div></div>
      </a>
    </div>

    <!-- CENTER HUB -->
    <div class="middle">
      <div class="hub-wrap">
        <svg class="hub-svg" viewBox="0 0 440 440">
          <defs>
            <radialGradient id="hubfill" cx="50%" cy="50%" r="50%">
              <stop offset="0" stop-color="#062a5e"/><stop offset="60%" stop-color="#031a45"/><stop offset="100%" stop-color="#02122f"/>
            </radialGradient>
            <filter id="ringglow" x="-30%" y="-30%" width="160%" height="160%">
              <feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
            </filter>
          </defs>
          <circle cx="220" cy="220" r="205" fill="none" stroke="#0a4aa0" stroke-width="1" opacity=".5"/>
          <circle class="ring-cw" cx="220" cy="220" r="188" fill="none" stroke="#1f7fe0" stroke-width="2" opacity=".65" filter="url(#ringglow)"/>
          <circle class="ring-ccw" cx="220" cy="220" r="176" fill="none" stroke="#29bfff" stroke-width="3" filter="url(#ringglow)"/>
          <circle class="ring-pulse" cx="220" cy="220" r="152" fill="url(#hubfill)" stroke="#2bd2ff" stroke-width="2.5" filter="url(#ringglow)"/>
          <circle class="ring-cw" cx="220" cy="220" r="120" fill="none" stroke="#0e88ff" stroke-width="1" stroke-dasharray="4 6" opacity=".7"/>
          <!-- progress arc accent -->
          <circle cx="220" cy="220" r="176" fill="none" stroke="#5fe0ff" stroke-width="4"
                  stroke-linecap="round" stroke-dasharray="470 1105" transform="rotate(-90 220 220)" opacity=".9" filter="url(#ringglow)"/>
          <!-- node ticks around inner ring -->
          <g stroke="#7ce6ff" stroke-width="2">
            <line x1="220" y1="72" x2="220" y2="60"/><line x1="220" y1="380" x2="220" y2="368"/>
            <line x1="72" y1="220" x2="60" y2="220"/><line x1="380" y1="220" x2="368" y2="220"/>
          </g>
        </svg>
        <div class="hub-core">
          <div class="hubtxt">
            <b>AIOps</b><strong>INVENTORY</strong><span>COMMAND CENTER</span>
            <svg class="wave" viewBox="0 0 150 20"><path d="M0 10 H40 l4 -7 l5 14 l4 -11 l4 8 l3 -4 H150"/></svg>
          </div>
        </div>
        <div class="health"><small>SYSTEM HEALTH</small><b>__HEALTH__</b></div>
      </div>
    </div>

    <!-- RIGHT COLUMN -->
    <div class="col r">
      <a class="card" href="/d/ardmatrix-vm-inventory/vm-inventory?orgId=1&var-site=All&var-rack=All&var-server=All&var-vm=All">
        <div class="ico"><svg viewBox="0 0 24 24">
          <path d="M12 3 L20 7 L20 16 L12 20 L4 16 L4 7 Z"/><path d="M4 7 L12 11 L20 7"/><line x1="12" y1="11" x2="12" y2="20"/></svg></div>
        <div class="body"><div class="num">__VM__</div><div class="lbl">VIRTUAL MACHINES</div>
          <div class="det">Running : <span class="g">__VMR__</span><span class="sep">|</span>Stopped : <span class="r">__VMS__</span></div></div>
      </a>
      <a class="card" href="/d/ardmatrix-application-inventory/application-inventory?orgId=1&var-site=All&var-application=All">
        <div class="ico"><svg viewBox="0 0 24 24">
          <rect x="4" y="4" width="7" height="7" rx="1.4"/><rect x="13" y="4" width="7" height="7" rx="1.4"/>
          <rect x="4" y="13" width="7" height="7" rx="1.4"/><rect x="13" y="13" width="7" height="7" rx="1.4"/></svg></div>
        <div class="body"><div class="num">__APP__</div><div class="lbl">APPLICATIONS</div>
          <div class="det">Healthy : <span class="g">__APPH__</span><span class="sep">|</span>Warning : <span class="y">__APPW__</span><span class="sep">|</span>Critical : <span class="r">__APPC__</span></div></div>
      </a>
      <a class="card" href="/d/ardmatrix-global-topology/global-data-center-topology?orgId=1">
        <div class="ico"><svg viewBox="0 0 24 24">
          <circle cx="12" cy="5" r="2.4"/><circle cx="5.5" cy="18" r="2.4"/><circle cx="18.5" cy="18" r="2.4"/>
          <line x1="11" y1="7" x2="6.7" y2="15.8"/><line x1="13" y1="7" x2="17.3" y2="15.8"/><line x1="8" y1="18" x2="16" y2="18"/></svg></div>
        <div class="body"><div class="num">__NET__</div><div class="lbl">NETWORK DEVICES</div>
          <div class="det">Online : <span class="g">__NETON__</span><span class="sep">|</span>Offline : <span class="r">__NETOFF__</span></div></div>
      </a>
    </div>
  </div>

  <!-- INTEL STRIP -->
  <div class="intel">
    <div class="ii" style="color:#ff5364">
      <div class="iico"><svg viewBox="0 0 24 24"><path d="M2 12 H7 l2 -7 l4 14 l2 -7 H22"/></svg></div>
      <div class="txt"><div class="t">ACTIVE ALERTS</div><div class="v">__ALERTS__</div>
        <div class="s">Critical : <b class="r">__ALERTC__</b> <span class="sep">|</span> Warning : <b class="y">__ALERTW__</b></div></div>
    </div>
    <div class="ii" style="color:#2fb7ff">
      <div class="iico"><svg viewBox="0 0 24 24"><path d="M12 3 L20 6 V11 C20 16 16.5 19.5 12 21 C7.5 19.5 4 16 4 11 V6 Z"/><path d="M9 12 l2.2 2.2 L15 10"/></svg></div>
      <div class="txt"><div class="t">SECURITY EVENTS</div><div class="v">__SEC__</div><div class="s">Last 24 Hours</div></div>
    </div>
    <div class="ii" style="color:#72df68">
      <div class="iico"><svg viewBox="0 0 24 24"><line x1="4" y1="20" x2="20" y2="20"/><rect x="6" y="12" width="3" height="6"/><rect x="11" y="8" width="3" height="10"/><rect x="16" y="5" width="3" height="13"/><path d="M6 9 L11 6 L16 3"/><path d="M16 3 h2.5 v2.5" fill="none"/></svg></div>
      <div class="txt"><div class="t">CAPACITY UTILIZATION</div><div class="v">__CAP__</div><div class="s">Average Across DCs</div></div>
    </div>
    <div class="ii" style="color:#b74cff">
      <div class="iico"><svg viewBox="0 0 24 24"><line x1="4" y1="20" x2="20" y2="20"/><path d="M4 16 L9 11 L13 14 L20 6"/><path d="M20 6 h-3 M20 6 v3" fill="none"/></svg></div>
      <div class="txt"><div class="t">PREDICTED ISSUES</div><div class="v">__PRED__</div><div class="s">Next 24 Hours</div></div>
    </div>
    <div class="ii" style="color:#22d5f5">
      <div class="iico"><svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="1.6"/><rect x="10" y="10" width="4" height="4"/>
        <line x1="9" y1="3.5" x2="9" y2="6.5"/><line x1="15" y1="3.5" x2="15" y2="6.5"/><line x1="9" y1="17.5" x2="9" y2="20.5"/><line x1="15" y1="17.5" x2="15" y2="20.5"/>
        <line x1="3.5" y1="9" x2="6.5" y2="9"/><line x1="3.5" y1="15" x2="6.5" y2="15"/><line x1="17.5" y1="9" x2="20.5" y2="9"/><line x1="17.5" y1="15" x2="20.5" y2="15"/></svg></div>
      <div class="txt"><div class="t">AI ANOMALIES</div><div class="v">__AI__</div><div class="s">Investigate Now</div></div>
    </div>
  </div>

  <!-- NAV -->
  <div class="nav">
    <a class="active" href="/d/ardmatrix-inventory-overview/data-center-inventory-overview?orgId=1"><svg viewBox="0 0 24 24"><path d="M4 11 L12 4 L20 11"/><path d="M6 10 V20 H18 V10"/></svg>OVERVIEW</a>
    <a href="/d/ardmatrix-server-inventory/server-inventory?orgId=1&var-site=All&var-rack=All&var-server=All"><svg viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="5" rx="1"/><rect x="4" y="14" width="16" height="5" rx="1"/><circle cx="7" cy="7.5" r="0.7" fill="#6fdcff" stroke="none"/><circle cx="7" cy="16.5" r="0.7" fill="#6fdcff" stroke="none"/></svg>SERVERS</a>
    <a href="/d/ardmatrix-global-topology/global-data-center-topology?orgId=1"><svg viewBox="0 0 24 24"><circle cx="6" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7.5 7.5 L11 16 M16.5 7.5 L13 16 M8 6 H16"/></svg>NETWORK</a>
    <a href="/d/ardmatrix-vm-inventory/vm-inventory?orgId=1&var-site=All&var-rack=All&var-server=All&var-vm=All"><svg viewBox="0 0 24 24"><path d="M12 3 L20 7 L20 16 L12 20 L4 16 L4 7 Z"/><path d="M4 7 L12 11 L20 7"/><line x1="12" y1="11" x2="12" y2="20"/></svg>VIRTUALIZATION</a>
    <a href="/d/ardmatrix-application-inventory/application-inventory?orgId=1&var-site=All&var-application=All"><svg viewBox="0 0 24 24"><rect x="4" y="4" width="7" height="7" rx="1"/><rect x="13" y="4" width="7" height="7" rx="1"/><rect x="4" y="13" width="7" height="7" rx="1"/><rect x="13" y="13" width="7" height="7" rx="1"/></svg>APPLICATIONS</a>
    <a><svg viewBox="0 0 24 24"><path d="M12 4 C8 4 5 7 5 11 c0 2 1 3 1 5 M12 4 c4 0 7 3 7 7 0 2 -1 3 -1 5"/><path d="M6 16 h12 M8 19 h8"/><circle cx="12" cy="10" r="1.4"/></svg>ANOMALIES</a>
    <a><svg viewBox="0 0 24 24"><path d="M4 18 L10 11 L14 15 L20 7"/><path d="M20 7 h-3 M20 7 v3"/></svg>FORECASTING</a>
    <a><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4"/><circle cx="12" cy="12" r="1" fill="#6fdcff" stroke="none"/></svg>RCA</a>
    <a><svg viewBox="0 0 24 24"><path d="M6 3 H15 L19 7 V21 H6 Z"/><path d="M14 3 V7 H19"/><line x1="9" y1="12" x2="16" y2="12"/><line x1="9" y1="16" x2="16" y2="16"/></svg>REPORTS</a>
    <a><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 2 v3 M12 19 v3 M2 12 h3 M19 12 h3 M5 5 l2 2 M17 17 l2 2 M19 5 l-2 2 M7 17 l-2 2"/></svg>SETTINGS</a>
  </div>

  <div class="foot">May 25, 2025&nbsp;&nbsp;|&nbsp;&nbsp;12:45:30 PM IST</div>
`;

// read a single-row table field by column name -> localized number, or em dash
function num(d,n){
  var s=d&&d.series&&d.series[0];
  var f=s&&s.fields&&s.fields.find(function(x){return x.name===n;});
  if(!f||!f.values) return "\u2014";
  var vals=f.values;
  var x=(typeof vals.get==="function")?vals.get(0):vals[0];
  return (x==null)?"\u2014":Number(x).toLocaleString();
}

function build(d){
  var g=function(n){return num(d,n);};
  var pct=function(n){var v=num(d,n);return v==="\u2014"?v:v+"%";};
  var map={
    "__BG__":IMG+"datacenter-background.png",
    "__LOGO__":IMG+"ardmatrix-aiops-transparent-final.png",
    "__DC__":g("Data Centers"),
    "__RACK__":g("Racks"),
    "__RACKU__":pct("Rack Utilization"),
    "__SRV__":g("Servers"),
    "__SRVH__":g("Server Healthy"),
    "__SRVW__":g("Server Warning"),
    "__SRVC__":g("Server Critical"),
    "__VM__":g("Virtual Machines"),
    "__VMR__":g("VM Running"),
    "__VMS__":g("VM Stopped"),
    "__APP__":g("Applications"),
    "__APPH__":g("App Healthy"),
    "__APPW__":g("App Warning"),
    "__APPC__":g("App Critical"),
    "__NET__":g("Network Devices"),
    "__NETON__":g("Network Online"),
    "__NETOFF__":g("Network Offline"),
    "__HEALTH__":pct("System Health"),
    "__ALERTS__":g("Open Alerts"),
    "__ALERTC__":g("Alerts Critical"),
    "__ALERTW__":g("Alerts Warning"),
    "__SEC__":g("Security Events"),
    "__CAP__":pct("Capacity"),
    "__PRED__":g("Predicted Issues"),
    "__AI__":g("AI Anomalies")
  };
  var out=HTML;
  for(var k in map){ out=out.split(k).join(map[k]); }
  return out;
}

function Panel(props){
  var rootRef=R.useRef(null);
  var offsetState=R.useState(null);
  var rootOffset=offsetState[0],setRootOffset=offsetState[1];
  var initialW=(typeof window!=="undefined"&&window.innerWidth)||props.width||1536;
  var initialH=(typeof window!=="undefined"&&window.innerHeight)||props.height||1024;
  var sizeState=R.useState({w:initialW,h:initialH});
  var viewport=sizeState[0],setViewport=sizeState[1];
  R.useEffect(function(){
    try{
      var u=new URL(location.href);
      if(location.pathname.indexOf("/d/")===0 && u.searchParams.get("kiosk")!=="1"){
        u.searchParams.set("kiosk","1"); location.replace(u.toString());
      }
    }catch(e){}
    var onResize=function(){setViewport({w:window.innerWidth,h:window.innerHeight});};
    window.addEventListener("resize",onResize);
    return function(){window.removeEventListener("resize",onResize);};
  },[]);
  R.useLayoutEffect(function(){
    if(rootRef.current&&rootOffset===null){
      var rect=rootRef.current.getBoundingClientRect();
      setRootOffset({x:-rect.left,y:-rect.top});
    }
  },[rootOffset]);
  var w=viewport.w, h=viewport.h;
  var s=Math.min(w/1536,h/1024);
  if(!isFinite(s)||s<=0){s=1;}
  var offx=(w-1536*s)/2,offy=(h-1024*s)/2;
  var stageStyle="position:absolute;left:"+offx+"px;top:"+offy+"px;width:1536px;height:1024px;transform:scale("+s+");transform-origin:top left";
  var full="<style>"+CSS+"</style><div class=\"stage\" style=\""+stageStyle+"\">"+build(props.data)+"</div>";
  return R.createElement("div",{ref:rootRef,className:"ardx",style:{position:"fixed",inset:"0",zIndex:1000,width:"100vw",height:"100vh",overflow:"hidden",transform:"translate("+(rootOffset?rootOffset.x:0)+"px,"+(rootOffset?rootOffset.y:0)+"px)"},dangerouslySetInnerHTML:{__html:full}});
}

exports("plugin", new P(Panel));
}}});
