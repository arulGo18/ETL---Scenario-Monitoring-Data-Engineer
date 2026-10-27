const DESIGN_HOST = window.location.origin;

const state = {
  runs: [],
  globalStats: null,
  generatedAt: null
};

function getTodayYMD() {
  const d = new Date();
  const pad = n => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
}

function fmtDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d)) return "—";
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const pad = (n) => String(n).padStart(2, "0");
  return `${pad(d.getDate())} ${months[d.getMonth()]} ${d.getFullYear()}, ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function fmtDuration(secs) {
  if (secs == null || isNaN(secs) || secs === 0) return "0s";
  const s = Math.round(secs);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  const rs = s % 60;
  if (m < 60) return `${m}m ${rs}s`;
  const h = Math.floor(m / 60);
  const rm = m % 60;
  return `${h}h ${rm}m ${rs}s`;
}

function statusBadge(status) {
  const s = (status || "UNKNOWN").toUpperCase();
  const cls = {SUCCESS:"success", FAILED:"failed", ABORTED:"failed", ERROR:"failed", RUNNING:"running", WARNING:"warning"}[s] || "unknown";
  return `<span class="badge ${cls}">${s}</span>`;
}

function getStatusIcon(status) {
  const s = (status || "").toUpperCase();
  if (s === "SUCCESS") return "✅";
  if (s === "FAILED" || s === "ABORTED") return "❌";
  if (s === "RUNNING") return "⏳";
  if (s === "WARNING") return "⚠️";
  return "❔";
}

function getExecutionLink(run) {
  const proj = encodeURIComponent(run.PROJECT_NAME);
  if (run.TYPE === "SCENARIO") {
    return `<a class="scenario-link" href="${DESIGN_HOST}/projects/${proj}/scenarios/" target="_blank"><span style="color:#8b5cf6">💻 [SCENARIO]</span> ${escape(run.SCENARIO_NAME)}</a>`;
  } else {
    return `<a class="scenario-link" href="${DESIGN_HOST}/projects/${proj}/jobs/" target="_blank"><span style="color:#3b82f6">⚙️ [JOB]</span> ${escape(run.SCENARIO_NAME)}</a>`;
  }
}

// FUNGSI BARU: Merender KPI secara statis dari data Global (Server)
function renderGlobalKpis(stats) {
  if (!stats) return;
  document.getElementById("kpi-total").textContent = stats.total;
  document.getElementById("kpi-success").textContent = stats.success;
  document.getElementById("kpi-failed").textContent = stats.failed;
  document.getElementById("kpi-running").textContent = stats.running;
  
  const avg = stats.count_duration > 0 ? (stats.sum_duration / stats.count_duration) : 0;
  document.getElementById("kpi-avg").textContent = fmtDuration(avg);
}

function runMatches(run) {
  const f_status = document.getElementById("f-status").value;
  const f_search = document.getElementById("f-search").value.toLowerCase();
  
  if (f_status && run.overall_status !== f_status) return false;
  if (f_search && !run.SCENARIO_NAME.toLowerCase().includes(f_search)) return false;
  
  return true;
}

function renderRuns(filteredRuns) {
  const container = document.getElementById("view-runs");
  if (!filteredRuns.length) {
    container.innerHTML = "<div style='text-align:center; padding:40px; color:#999; font-weight:bold; font-size: 16px;'>Tidak ada eksekusi yang sesuai filter/pencarian di tanggal ini.</div>";
    return;
  }
  
  filteredRuns.sort((a,b) => (b.run_start || "").localeCompare(a.run_start || ""));

  const html = filteredRuns.map((run) => {
    const borderClass = run.overall_status === 'SUCCESS' ? 'success-border' : 
                        (run.overall_status === 'FAILED' ? 'failed-border' : 
                        (run.overall_status === 'RUNNING' ? 'running-border' : ''));

    return `
      <div class="run-card ${borderClass}">
        <div class="run-head">
          <div class="run-icon">${getStatusIcon(run.overall_status)}</div>
          <div class="run-scenario">${getExecutionLink(run)}</div>
          <div class="run-meta-group">
            <span class="run-date">${fmtDate(run.run_start)}</span>
            <span class="run-duration">${fmtDuration(run.total_duration)}</span>
          </div>
          <div class="run-status-cell">${statusBadge(run.overall_status)}</div>
        </div>
      </div>`;
  }).join("");

  container.innerHTML = html;
}

function refreshView() {
  const filteredRuns = state.runs.filter(run => runMatches(run));
  // KAMI TIDAK LAGI MEMANGGIL FUNGSI KPI DI SINI
  document.getElementById("result-count").textContent = `${filteredRuns.length} eksekusi ditampilkan pada tanggal ini`;
  renderRuns(filteredRuns);
}

function loadData() {
  document.getElementById("subtitle").textContent = "Memuat data dari server...";
  const selectedDate = document.getElementById("f-date").value || getTodayYMD();
  
  const base = (typeof getWebAppBackendUrl === "function") ? getWebAppBackendUrl("/data") : "/data";
  const url = `${base}?date=${selectedDate}`;
  
  fetch(url).then(r => r.json()).then(resp => {
    if(resp.error) {
      document.getElementById("subtitle").textContent = "API Error: " + resp.error;
      return;
    }
    state.runs = resp.runs || [];
    state.globalStats = resp.global_stats || null;
    state.generatedAt = resp.generated_at;

    // Render KPI dari Global Stats secara paten
    renderGlobalKpis(state.globalStats);

    document.getElementById("subtitle").textContent = `Dataiku API • Data Tanggal: ${selectedDate} • Diperbarui pada ${fmtDate(state.generatedAt)}`;
    refreshView(); // Ini hanya memperbarui tabel, tidak mengubah KPI
  }).catch(err => {
    document.getElementById("subtitle").textContent = "Gagal memuat data: " + err.message;
  });
}

function bindUi() {
  document.getElementById("f-date").value = getTodayYMD();
  
  document.getElementById("f-search").addEventListener("input", refreshView);
  document.getElementById("f-date").addEventListener("change", loadData);
  document.getElementById("f-status").addEventListener("change", refreshView);
  
  document.getElementById("btn-refresh").addEventListener("click", loadData);
  document.getElementById("btn-clear").addEventListener("click", () => {
    document.getElementById("f-search").value = ""; 
    document.getElementById("f-date").value = getTodayYMD();
    document.getElementById("f-status").value = "";
    loadData(); 
  });
}

bindUi();
loadData();

function escape(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
}