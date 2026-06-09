#!/bin/bash

# ─────────────────────────────────────────
#  ZiCharge - Maestro Smoke Test Report Generator
#  With ADB Screen Recording for each flow
# ─────────────────────────────────────────

PROJECT_DIR="$HOME/Downloads/Maestro/SuperSide"
SUITE_FILE="$PROJECT_DIR/suites/smoke.yaml"
REPORTS_DIR="$PROJECT_DIR/reports"
VIDEOS_DIR="$REPORTS_DIR/videos"
MOBILE_NUMBER="${1:-1617539764}"
PASSWORD="${2:-Password100@}"
DEVICE="ZA2233WW3N"
APP_NAME="ZiCharge Super_User"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_FILE="$REPORTS_DIR/TestReport_ZiChargePersonalProfile_Smoke_${TIMESTAMP}.html"

mkdir -p "$REPORTS_DIR"
mkdir -p "$VIDEOS_DIR"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   ZiCharge - Maestro Smoke Suite     ║"
echo "║       With ADB Screen Recording      ║"
echo "╚══════════════════════════════════════╝"
echo "📄 Report File : $REPORT_FILE"
echo "🎥 Videos Dir  : $VIDEOS_DIR"
echo "⏰ Started     : $(date)"
echo ""

# ── Parse sub-flows from smoke.yaml ─────────────────────────────
mapfile -t RAW_FLOWS < <(grep '^\- runFlow:' "$SUITE_FILE" | sed 's/- runFlow: //')

if [ ${#RAW_FLOWS[@]} -eq 0 ]; then
    echo "❌ No runFlow entries found in $SUITE_FILE"
    exit 1
fi

echo "Found ${#RAW_FLOWS[@]} flow(s) to run."
echo ""

# ── Run each sub-flow individually ──────────────────────────────
declare -a FLOW_NAMES
declare -a FLOW_FILES
declare -a FLOW_RESULTS
declare -a FLOW_DURATIONS
declare -a FLOW_LOGS
declare -a FLOW_VIDEOS

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FULL_LOG=""
TOTAL_START=$(date +%s%N)

for REL_PATH in "${RAW_FLOWS[@]}"; do
    ABS_PATH="$(realpath "$PROJECT_DIR/suites/$REL_PATH")"
    FLOW_FILE=$(basename "$ABS_PATH")
    FLOW_NAME="${FLOW_FILE%.yaml}"
    TOTAL=$((TOTAL + 1))

    echo "  ▶ Running: $FLOW_NAME"

    # ── Start ADB screen recording ───────────────────────────────
    DEVICE_VIDEO_PATH="/sdcard/maestro_${FLOW_NAME}_${TIMESTAMP}.mp4"
    LOCAL_VIDEO_PATH="$VIDEOS_DIR/${FLOW_NAME}_${TIMESTAMP}.mp4"

    echo "    🎥 Starting screen recording..."
    adb -s "$DEVICE" shell screenrecord --bit-rate 4000000 "$DEVICE_VIDEO_PATH" &
    ADB_PID=$!
    sleep 1

    # ── Run the Maestro flow ─────────────────────────────────────
    FLOW_START=$(date +%s%N)
    FLOW_OUTPUT=$(maestro --device "$DEVICE" test \
        --env Mobile_Number="$MOBILE_NUMBER" \
        --env Password="$PASSWORD" \
        "$ABS_PATH" 2>&1)
    EXIT_CODE=$?
    FLOW_END=$(date +%s%N)

    # ── Stop ADB screen recording ────────────────────────────────
    echo "    🛑 Stopping screen recording..."
    kill "$ADB_PID" 2>/dev/null
    sleep 2

    # ── Pull video from device ───────────────────────────────────
    echo "    📥 Pulling video from device..."
    adb -s "$DEVICE" pull "$DEVICE_VIDEO_PATH" "$LOCAL_VIDEO_PATH" 2>/dev/null
    adb -s "$DEVICE" shell rm "$DEVICE_VIDEO_PATH" 2>/dev/null

    if [ -f "$LOCAL_VIDEO_PATH" ]; then
        echo "    ✅ Video saved: ${FLOW_NAME}_${TIMESTAMP}.mp4"
        FLOW_VIDEOS+=("${FLOW_NAME}_${TIMESTAMP}.mp4")
    else
        echo "    ⚠️  Video not saved"
        FLOW_VIDEOS+=("")
    fi

    # ── Calculate duration ───────────────────────────────────────
    DURATION_MS=$(( (FLOW_END - FLOW_START) / 1000000 ))
    DURATION_SEC=$(echo "scale=2; $DURATION_MS / 1000" | bc)

    FULL_LOG+="=== $FLOW_NAME ===\n$FLOW_OUTPUT\n\n"

    if [ $EXIT_CODE -eq 0 ]; then
        RESULT="Passed"
        PASSED=$((PASSED + 1))
        echo "    ✅ PASSED (${DURATION_SEC}s)"
    else
        RESULT="Failed"
        FAILED=$((FAILED + 1))
        echo "    ❌ FAILED (${DURATION_SEC}s)"
    fi

    echo ""

    FLOW_NAMES+=("$FLOW_NAME")
    FLOW_FILES+=("$FLOW_FILE")
    FLOW_RESULTS+=("$RESULT")
    FLOW_DURATIONS+=("${DURATION_SEC}s")
    FLOW_LOGS+=("$(echo "$FLOW_OUTPUT" | sed 's/</\&lt;/g; s/>/\&gt;/g')")
done

TOTAL_END=$(date +%s%N)
TOTAL_MS=$(( (TOTAL_END - TOTAL_START) / 1000000 ))
TOTAL_DURATION=$(echo "scale=2; $TOTAL_MS / 1000" | bc)

echo "────────────────────────────────────────"
echo "  Total: $TOTAL | ✅ Passed: $PASSED | ❌ Failed: $FAILED | ⏭ Skipped: $SKIPPED"
echo "  Duration: ${TOTAL_DURATION}s"
echo "  Videos saved in: $VIDEOS_DIR"
echo "────────────────────────────────────────"
echo ""

# ── Overall status ───────────────────────────────────────────────
if [ $FAILED -eq 0 ]; then
    OVERALL_STATUS="✅ ALL SMOKE TESTS PASSED"
    STATUS_CLASS="all-passed"
else
    OVERALL_STATUS="❌ $FAILED TEST(S) FAILED"
    STATUS_CLASS="some-failed"
fi

# ── Build HTML table rows ────────────────────────────────────────
TABLE_ROWS=""
for i in "${!FLOW_NAMES[@]}"; do
    NUM=$((i + 1))
    NAME="${FLOW_NAMES[$i]}"
    FILE="${FLOW_FILES[$i]}"
    RESULT="${FLOW_RESULTS[$i]}"
    DURATION="${FLOW_DURATIONS[$i]}"
    LOG="${FLOW_LOGS[$i]}"
    VIDEO="${FLOW_VIDEOS[$i]}"

    if [ "$RESULT" = "Passed" ]; then
        BADGE='<span class="badge pass">✅ Passed</span>'
        ROW_CLASS="row-pass"
    else
        BADGE='<span class="badge fail">❌ Failed</span>'
        ROW_CLASS="row-fail"
    fi

    if [ -n "$VIDEO" ]; then
        VIDEO_CELL="<a class='video-link' href='videos/$VIDEO'>🎥 Watch</a>"
    else
        VIDEO_CELL="<span class='no-video'>—</span>"
    fi

    TABLE_ROWS+="
    <tr class='$ROW_CLASS'>
      <td>$NUM</td>
      <td>$NAME</td>
      <td>$FILE</td>
      <td>$DURATION</td>
      <td>$BADGE</td>
      <td>$VIDEO_CELL</td>
    </tr>
    <tr class='log-row'>
      <td colspan='6'>
        <details>
          <summary>▶ View Log</summary>
          <pre>$LOG</pre>
        </details>
      </td>
    </tr>"
done

# ── Write HTML ───────────────────────────────────────────────────
cat > "$REPORT_FILE" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>ZiCharge - Smoke Test Report</title>
<link href="https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet"/>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  :root {
    --bg: #0b0f1a; --surface: #111827; --surface2: #1a2235; --border: #1e2d45;
    --accent: #3b82f6; --accent2: #06b6d4; --green: #22c55e; --red: #ef4444;
    --orange: #f59e0b; --text: #e2e8f0; --muted: #64748b;
    --font: 'Syne', sans-serif; --mono: 'JetBrains Mono', monospace;
  }
  body { background: var(--bg); color: var(--text); font-family: var(--font); min-height: 100vh; padding: 40px 20px; }
  .wrapper { max-width: 1100px; margin: 0 auto; }
  .header {
    background: linear-gradient(135deg, #1a2a4a 0%, #0f1e3a 60%, #0b1628 100%);
    border: 1px solid var(--border); border-radius: 16px; padding: 36px 40px;
    margin-bottom: 24px; position: relative; overflow: hidden;
  }
  .header::before {
    content: ''; position: absolute; top: -60px; right: -60px;
    width: 220px; height: 220px; border-radius: 50%;
    background: radial-gradient(circle, rgba(59,130,246,0.15) 0%, transparent 70%);
  }
  .header .subtitle { color: var(--accent2); font-size: 0.8rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; margin-bottom: 10px; }
  .header h1 { font-size: 2rem; font-weight: 800; background: linear-gradient(90deg, #60a5fa, #06b6d4); -webkit-background-clip: text; -webkit-text-fill-color: transparent; margin-bottom: 8px; }
  .header p { color: var(--muted); font-size: 0.85rem; font-family: var(--mono); }
  .status-banner { border-radius: 12px; padding: 18px; text-align: center; font-size: 1.1rem; font-weight: 700; letter-spacing: 0.05em; margin-bottom: 24px; border: 1px solid; }
  .all-passed { background: rgba(34,197,94,0.08); border-color: rgba(34,197,94,0.3); color: var(--green); }
  .some-failed { background: rgba(239,68,68,0.08); border-color: rgba(239,68,68,0.3); color: var(--red); }
  .stats { display: grid; grid-template-columns: repeat(5, 1fr); gap: 16px; margin-bottom: 24px; }
  .stat-card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 24px 16px; text-align: center; }
  .stat-card .number { font-size: 2rem; font-weight: 800; font-family: var(--mono); display: block; margin-bottom: 6px; }
  .stat-card .label { color: var(--muted); font-size: 0.8rem; }
  .c-blue { color: var(--accent); } .c-green { color: var(--green); } .c-red { color: var(--red); }
  .c-orange { color: var(--orange); } .c-purple { color: #a78bfa; }

  /* ── Pie Chart Section ── */
  .chart-section {
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    padding: 32px; margin-bottom: 24px;
    display: flex; align-items: center; gap: 48px; flex-wrap: wrap;
  }
  .chart-title { font-size: 1rem; font-weight: 700; margin-bottom: 24px; color: var(--text); }
  .chart-container { position: relative; width: 200px; height: 200px; flex-shrink: 0; }
  .chart-container canvas { width: 200px !important; height: 200px !important; }
  .chart-legend { flex: 1; min-width: 200px; }
  .legend-item { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
  .legend-dot { width: 14px; height: 14px; border-radius: 50%; flex-shrink: 0; }
  .legend-info { flex: 1; }
  .legend-label { font-size: 0.85rem; color: var(--muted); }
  .legend-value { font-size: 1.2rem; font-weight: 800; font-family: var(--mono); }
  .legend-pct { font-size: 0.8rem; color: var(--muted); margin-left: 6px; }
  .center-text {
    position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
    text-align: center; pointer-events: none;
  }
  .center-text .big { font-size: 2rem; font-weight: 800; font-family: var(--mono); color: var(--text); }
  .center-text .small { font-size: 0.7rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; }

  .table-wrap { background: var(--surface); border: 1px solid var(--border); border-radius: 16px; overflow: hidden; margin-bottom: 24px; }
  table { width: 100%; border-collapse: collapse; }
  thead tr { background: linear-gradient(90deg, var(--accent) 0%, var(--accent2) 100%); }
  thead th { padding: 14px 20px; text-align: left; font-size: 0.8rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: #fff; }
  tbody tr { border-bottom: 1px solid var(--border); transition: background 0.2s; }
  tbody tr:hover { background: var(--surface2); }
  tbody td { padding: 14px 20px; font-size: 0.9rem; font-family: var(--mono); }
  .row-fail td:first-child { border-left: 3px solid var(--red); }
  .row-pass td:first-child { border-left: 3px solid var(--green); }
  .log-row td { padding: 0 20px 12px; background: var(--bg); }
  .log-row:hover { background: var(--bg) !important; }
  details summary { cursor: pointer; color: var(--accent); font-size: 0.8rem; padding: 8px 0 4px; user-select: none; }
  details pre { background: #060a12; border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; font-size: 0.75rem; color: #94a3b8; overflow-x: auto; white-space: pre-wrap; word-break: break-all; max-height: 300px; overflow-y: auto; margin-top: 6px; }
  .badge { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 0.8rem; font-weight: 600; font-family: var(--font); }
  .badge.pass { background: rgba(34,197,94,0.12); color: var(--green); border: 1px solid rgba(34,197,94,0.3); }
  .badge.fail { background: rgba(239,68,68,0.12); color: var(--red); border: 1px solid rgba(239,68,68,0.3); }
  .video-link { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 0.8rem; font-weight: 600; background: rgba(59,130,246,0.12); color: var(--accent); border: 1px solid rgba(59,130,246,0.3); text-decoration: none; }
  .video-link:hover { background: rgba(59,130,246,0.25); }
  .no-video { color: var(--muted); }
  .full-log { background: var(--surface); border: 1px solid var(--border); border-radius: 16px; overflow: hidden; }
  .full-log-header { padding: 16px 24px; font-weight: 700; font-size: 0.95rem; border-bottom: 1px solid var(--border); background: var(--surface2); }
  .full-log pre { padding: 20px 24px; font-family: var(--mono); font-size: 0.78rem; color: #64748b; white-space: pre-wrap; word-break: break-all; max-height: 400px; overflow-y: auto; }
  @media (max-width: 700px) {
    .stats { grid-template-columns: repeat(2, 1fr); }
    thead th:nth-child(3), tbody td:nth-child(3) { display: none; }
    .chart-section { flex-direction: column; align-items: center; }
  }
</style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <div class="subtitle">💨 Smoke Suite</div>
    <h1>$APP_NAME — Smoke Test Report</h1>
    <p>Generated: $TIMESTAMP &nbsp;|&nbsp; App: com.newroztech.gamewallet &nbsp;|&nbsp; Suite: smoke.yaml</p>
  </div>

  <div class="status-banner $STATUS_CLASS">$OVERALL_STATUS</div>

  <div class="stats">
    <div class="stat-card"><span class="number c-blue">$TOTAL</span><span class="label">Total Flows</span></div>
    <div class="stat-card"><span class="number c-green">$PASSED</span><span class="label">Passed</span></div>
    <div class="stat-card"><span class="number c-red">$FAILED</span><span class="label">Failed</span></div>
    <div class="stat-card"><span class="number c-orange">$SKIPPED</span><span class="label">Skipped</span></div>
    <div class="stat-card"><span class="number c-purple">${TOTAL_DURATION}s</span><span class="label">Total Duration</span></div>
  </div>

  <!-- ── Pie Chart ── -->
  <div class="chart-section">
    <div>
      <div class="chart-title">📊 Test Results Breakdown</div>
      <div class="chart-container">
        <canvas id="pieChart"></canvas>
        <div class="center-text">
          <div class="big">$TOTAL</div>
          <div class="small">Total</div>
        </div>
      </div>
    </div>
    <div class="chart-legend">
      <div class="legend-item">
        <div class="legend-dot" style="background:#22c55e;"></div>
        <div class="legend-info">
          <div class="legend-label">Passed</div>
          <div><span class="legend-value" style="color:#22c55e;">$PASSED</span><span class="legend-pct" id="pct-pass"></span></div>
        </div>
      </div>
      <div class="legend-item">
        <div class="legend-dot" style="background:#ef4444;"></div>
        <div class="legend-info">
          <div class="legend-label">Failed</div>
          <div><span class="legend-value" style="color:#ef4444;">$FAILED</span><span class="legend-pct" id="pct-fail"></span></div>
        </div>
      </div>
      <div class="legend-item">
        <div class="legend-dot" style="background:#f59e0b;"></div>
        <div class="legend-info">
          <div class="legend-label">Skipped</div>
          <div><span class="legend-value" style="color:#f59e0b;">$SKIPPED</span><span class="legend-pct" id="pct-skip"></span></div>
        </div>
      </div>
    </div>
  </div>

  <div class="table-wrap">
    <table>
      <thead>
        <tr><th>#</th><th>Flow Name</th><th>File</th><th>Duration</th><th>Result</th><th>🎥 Video</th></tr>
      </thead>
      <tbody>
        $TABLE_ROWS
      </tbody>
    </table>
  </div>

  <div class="full-log">
    <div class="full-log-header">📋 Maestro Execution Log</div>
    <pre>$(echo -e "$FULL_LOG" | sed 's/</\&lt;/g; s/>/\&gt;/g')</pre>
  </div>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.min.js"></script>
<script>
  const total  = $TOTAL;
  const passed = $PASSED;
  const failed = $FAILED;
  const skipped = $SKIPPED;

  // Percentages
  const pPass = total > 0 ? ((passed  / total) * 100).toFixed(1) : 0;
  const pFail = total > 0 ? ((failed  / total) * 100).toFixed(1) : 0;
  const pSkip = total > 0 ? ((skipped / total) * 100).toFixed(1) : 0;

  document.getElementById('pct-pass').textContent = pPass + '%';
  document.getElementById('pct-fail').textContent = pFail + '%';
  document.getElementById('pct-skip').textContent = pSkip + '%';

  const data = [passed, failed, skipped];
  const allZero = data.every(v => v === 0);

  new Chart(document.getElementById('pieChart'), {
    type: 'doughnut',
    data: {
      labels: ['Passed', 'Failed', 'Skipped'],
      datasets: [{
        data: allZero ? [1, 0, 0] : data,
        backgroundColor: ['#22c55e', '#ef4444', '#f59e0b'],
        borderColor: '#111827',
        borderWidth: 3,
        hoverOffset: 8
      }]
    },
    options: {
      cutout: '72%',
      plugins: { legend: { display: false }, tooltip: {
        callbacks: {
          label: ctx => {
            const val = data[ctx.dataIndex];
            const pct = total > 0 ? ((val / total) * 100).toFixed(1) : 0;
            return ' ' + ctx.label + ': ' + val + '  (' + pct + '%)';
          }
        }
      }},
      animation: { animateRotate: true, duration: 900 }
    }
  });
</script>
</body>
</html>
HTMLEOF

echo "✅ Report saved to:"
echo "   $REPORT_FILE"
echo ""
echo "🎥 Videos saved to:"
echo "   $VIDEOS_DIR"
echo ""
xdg-open "$REPORT_FILE" 2>/dev/null || echo "🌐 Open manually in browser: file://$REPORT_FILE"
