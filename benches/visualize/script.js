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
  // Load from actual JSON files
  fetch('../results/rust-baseline.json')
    .then(res => res.json())
    .then(data => { 
      allData = data; 
      renderTable(); 
      renderChart(); 
      updateStats();
    })
    .catch(err => {
      console.warn('Failed to load rust-baseline.json, using mock data:', err);
      allData = mockData;
      renderTable();
      renderChart();
      updateStats();
    });
}

// Helper: extract mean time from rust field (supports both old and new format)
function getRustTime(item) {
  if (typeof item.rust === 'number') {
    return item.rust; // old format
  } else if (item.rust && typeof item.rust === 'object') {
    return item.rust.mean_ms; // new format
  }
  return 0;
}

// Helper: extract fortran time (supports both old and new format)
function getFortranTime(item) {
  if (typeof item.fortran === 'number') {
    return item.fortran; // old format
  } else if (item.fortran && typeof item.fortran === 'object') {
    return item.fortran.mean_ms; // new format
  }
  return null;
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
    const rustTime = getRustTime(item);
    const fortranTime = getFortranTime(item);
    const speedup = fortranTime ? (rustTime / fortranTime).toFixed(2) : '-';
    const status = fortranTime 
      ? (fortranTime < rustTime ? 'faster' : 'complete')
      : 'pending';
    const statusText = fortranTime 
      ? (fortranTime < rustTime ? '⚡ Быстрее' : '✓ Готово')
      : '⏳ Ожидание';
    
    // Show confidence interval if available
    const rustCI = item.rust && typeof item.rust === 'object' && item.rust.ci_lower_ms
      ? ` [${item.rust.ci_lower_ms.toFixed(2)}, ${item.rust.ci_upper_ms.toFixed(2)}]`
      : '';
    
    return `
      <tr>
        <td><strong>${item.operation}</strong>.${item.name}</td>
        <td>${item.size}</td>
        <td>${rustTime.toFixed(2)}${rustCI}</td>
        <td>${fortranTime ? fortranTime.toFixed(2) : '-'}</td>
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
      data: filtered.map(d => getRustTime(d)),
      backgroundColor: 'rgba(102, 126, 234, 0.6)',
      borderColor: 'rgba(102, 126, 234, 1)',
      borderWidth: 2
    });
    
    if (filtered.some(d => getFortranTime(d))) {
      datasets.push({
        label: 'Fortran (мс)',
        data: filtered.map(d => getFortranTime(d)),
        backgroundColor: 'rgba(245, 87, 108, 0.6)',
        borderColor: 'rgba(245, 87, 108, 1)',
        borderWidth: 2
      });
    }
  } else if (metric === 'speedup' && filtered.some(d => getFortranTime(d))) {
    datasets.push({
      label: 'Speedup (x)',
      data: filtered.map(d => {
        const rust = getRustTime(d);
        const fortran = getFortranTime(d);
        return fortran ? (rust / fortran) : null;
      }),
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
  const rustData = filtered.map(d => getRustTime(d));
  const fortranData = filtered.filter(d => getFortranTime(d)).map(d => getFortranTime(d));
  
  const rustAvg = rustData.length > 0 
    ? (rustData.reduce((a, b) => a + b, 0) / rustData.length).toFixed(2)
    : '-';
  
  const fortranAvg = fortranData.length > 0
    ? (fortranData.reduce((a, b) => a + b, 0) / fortranData.length).toFixed(2)
    : '-';
  
  const speedup = (rustAvg !== '-' && fortranAvg !== '-')
    ? (parseFloat(rustAvg) / parseFloat(fortranAvg)).toFixed(2) + 'x'
    : '-';
  
  document.getElementById('rust-avg').textContent = rustAvg !== '-' ? rustAvg + ' мс' : '-';
  document.getElementById('fortran-avg').textContent = fortranAvg !== '-' ? fortranAvg + ' мс' : '-';
  document.getElementById('speedup').textContent = speedup;
}

