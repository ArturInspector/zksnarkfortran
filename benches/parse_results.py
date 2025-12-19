import json
import os
from pathlib import Path

def parse_criterion_results():
    """Parse Criterion JSON results and convert to dashboard format."""
    criterion_base = Path("target/criterion")
    results = []
    
    if not criterion_base.exists():
        print(f"Error: {criterion_base} does not exist. Run benchmarks first:")
        print("  cargo bench --bench polynomial-bench")
        return
    
    # Groups are directly in target/criterion/ (multilinear, univariate, eq_polynomial)
    for group_name in ["multilinear", "univariate", "eq_polynomial"]:
        group_dir = criterion_base / group_name
        if not group_dir.exists():
            continue
        
        # Each benchmark operation has its own directory (evaluate, bind_poly_var_top, etc.)
        for op_dir in group_dir.iterdir():
            if not op_dir.is_dir():
                continue
            
            op_name = op_dir.name
            
            # Size directories (10, 12, 14, etc.) or direct benchmark.json
            for size_dir in op_dir.iterdir():
                if not size_dir.is_dir():
                    continue
                
                # Try to parse size from directory name
                try:
                    size = int(size_dir.name)
                except ValueError:
                    # Not a size directory, skip
                    continue
                
                # mean time
                json_file = size_dir / "new" / "estimates.json"
                if not json_file.exists():
                    continue
                
                try:
                    with open(json_file) as f:
                        data = json.load(f)
                    
                    # extract mean statistics
                    mean_data = data.get("mean", {})
                    mean_ns = mean_data.get("point_estimate", 0)
                    mean_ms = mean_ns / 1_000_000.0
                    mean_ci = mean_data.get("confidence_interval", {})
                    mean_std_err = mean_data.get("standard_error", 0) / 1_000_000.0
                    
                    # extract median for comparison
                    median_data = data.get("median", {})
                    median_ns = median_data.get("point_estimate", 0)
                    median_ms = median_ns / 1_000_000.0
                    
                    results.append({
                        "operation": group_name,
                        "name": op_name,
                        "size": size,
                        "rust": {
                            "mean_ms": round(mean_ms, 4),
                            "median_ms": round(median_ms, 4),
                            "std_error_ms": round(mean_std_err, 4),
                            "ci_lower_ms": round(mean_ci.get("lower_bound", 0) / 1_000_000.0, 4),
                            "ci_upper_ms": round(mean_ci.get("upper_bound", 0) / 1_000_000.0, 4),
                            "confidence_level": mean_ci.get("confidence_level", 0.95)
                        },
                        "fortran": None,
                        "unit": "ms"
                    })
                    
                except Exception as e:
                    print(f"Warning: Failed to parse {json_file}: {e}")
                    continue
    results_dir = Path("benches/results")
    results_dir.mkdir(parents=True, exist_ok=True)
    output_file = results_dir / "rust-baseline.json"
    with open(output_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f" parsed {len(results)} benchmark results")
    print(f" way to save {output_file}")
    



    for op in ["multilinear", "univariate", "eq_polynomial"]:
        op_results = [r for r in results if r["operation"] == op]
        if op_results:
            print(f"  {op}: {len(op_results)} benchmarks")

if __name__ == "__main__":
    parse_criterion_results()
