// Simple benchmark dashboard for Nova SNARK polynomial operations
// Loads results from JSON files and displays them

let chart = null;
let allData = [];

// Mock data structure (replace with actual JSON loading)
const mockData = [
  { operation: 'multilinear', name: 'evaluate', size: 10, rust: 2.5, fortran: null, unit: 'ms' },
  { operation: 'multilinear', name: 'evaluate', size: 12, rust: 8.3, fortran: null, unit: 'ms' },
  { operation: 'multilinear', name: 'evaluate', size: 14, rust: 32.1, fortran: null, unit: 'ms' },
  { operation: 'univariate', name: 'evaluate', size: 100, rust: 0.15, fortran: null, unit: 'ms' },
  { operation: 'univariate', name: 'evaluate', size: 500, rust: 0.78, fortran: null, unit: 'ms' },
  { operation: 'eq_polynomial', name: 'evals_from_points', size: 16, rust: 12.4, fortran: null, unit: 'ms' },
];

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
  loadData();
  setupFilters();
  renderTable();
  renderChart();
  updateStats();
});

function loadData() {
  // TODO: Load from actual JSON files
  // fetch('results/rust-baseline.json')
  //   .then(res => res.json())
  //   .then(data => { allData = data; renderTable(); renderChart(); });
  
  allData = mockData;
}

function setupFilters() {
  const opFilter = document.getElementById('operation-filter');
  const metricFilter = document.getElementById('metric-filter');
  
  opFilter.addEventListener('change', () => {
    renderTable();
    renderChart();
  });
  
  metricFilter.addEventListener('change', () => {
    renderChart();
  });
}

function getFilteredData() {
  const opFilter = document.getElementById('operation-filter').value;
  return allData.filter(d => opFilter === 'all' || d.operation === opFilter);
}

function renderTable() {
  const tbody = document.getElementById('results-body');
  const filtered = getFilteredData();
  
  tbody.innerHTML = filtered.map(item => {
    const speedup = item.fortran ? (item.rust / item.fortran).toFixed(2) : '-';
    const status = item.fortran 
      ? (item.fortran < item.rust ? 'faster' : 'complete')
      : 'pending';
    const statusText = item.fortran 
      ? (item.fortran < item.rust ? '⚡ Быстрее' : '✓ Готово')
      : '⏳ Ожидание';
    
    return `
      <tr>
        <td><strong>${item.operation}</strong>.${item.name}</td>
        <td>${item.size}</td>
        <td>${item.rust.toFixed(2)}</td>
        <td>${item.fortran ? item.fortran.toFixed(2) : '-'}</td>
        <td>${speedup !== '-' ? speedup + 'x' : '-'}</td>
        <td><span class="status-badge ${status}">${statusText}</span></td>
      </tr>
    `;
  }).join('');
}

function renderChart() {
  const ctx = document.getElementById('performance-chart').getContext('2d');
  const filtered = getFilteredData();
  const metric = document.getElementById('metric-filter').value;
  
  // Group by operation and size
  const datasets = [];
  const labels = [...new Set(filtered.map(d => `${d.operation}.${d.name} (${d.size})`))];
  
  if (metric === 'time') {
    datasets.push({
      label: 'Rust (мс)',
      data: filtered.map(d => d.rust),
      backgroundColor: 'rgba(102, 126, 234, 0.6)',
      borderColor: 'rgba(102, 126, 234, 1)',
      borderWidth: 2
    });
    
    if (filtered.some(d => d.fortran)) {
      datasets.push({
        label: 'Fortran (мс)',
        data: filtered.map(d => d.fortran || null),
        backgroundColor: 'rgba(245, 87, 108, 0.6)',
        borderColor: 'rgba(245, 87, 108, 1)',
        borderWidth: 2
      });
    }
  } else if (metric === 'speedup' && filtered.some(d => d.fortran)) {
    datasets.push({
      label: 'Speedup (x)',
      data: filtered.map(d => d.fortran ? (d.rust / d.fortran) : null),
      backgroundColor: 'rgba(240, 147, 251, 0.6)',
      borderColor: 'rgba(240, 147, 251, 1)',
      borderWidth: 2
    });
  }
  
  if (chart) {
    chart.destroy();
  }
  
  chart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: labels,
      datasets: datasets
    },
    options: {
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        legend: {
          position: 'top',
        },
        title: {
          display: true,
          text: metric === 'time' ? 'Время выполнения (мс)' : 'Speedup (ускорение)'
        }
      },
      scales: {
        y: {
          beginAtZero: true,
          title: {
            display: true,
            text: metric === 'time' ? 'Время (мс)' : 'Speedup (x)'
          }
        }
      }
    }
  });
}

function updateStats() {
  const filtered = getFilteredData();
  const rustData = filtered.map(d => d.rust);
  const fortranData = filtered.filter(d => d.fortran).map(d => d.fortran);
  
  const rustAvg = rustData.length > 0 
    ? (rustData.reduce((a, b) => a + b, 0) / rustData.length).toFixed(2)
    : '-';
  
  const fortranAvg = fortranData.length > 0
    ? (fortranData.reduce((a, b) => a + b, 0) / fortranData.length).toFixed(2)
    : '-';
  
  const speedup = (rustAvg !== '-' && fortranAvg !== '-')
    ? (rustAvg / fortranAvg).toFixed(2) + 'x'
    : '-';
  
  document.getElementById('rust-avg').textContent = rustAvg !== '-' ? rustAvg + ' мс' : '-';
  document.getElementById('fortran-avg').textContent = fortranAvg !== '-' ? fortranAvg + ' мс' : '-';
  document.getElementById('speedup').textContent = speedup;
}

