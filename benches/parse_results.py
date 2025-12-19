import json
import os
from pathlib import Path

def parse_criterion_results():
    """Parse Criterion JSON results and convert to dashboard format."""
    criterion_dir = Path("target/criterion/polynomial_ops")
    results = []
    
    if not criterion_dir.exists():
        print(f"Error: {criterion_dir} does not exist. Run benchmarks first:")
        print("  cargo bench --bench polynomial-bench")
        return
    
    # map -> result
    for group_dir in criterion_dir.iterdir():
        if not group_dir.is_dir():
            continue
            
        group_name = group_dir.name  # okeey name
        
        for bench_dir in group_dir.iterdir():
            if not bench_dir.is_dir():
                continue
            
            # benchmark
            # Format: "name-size" or just "name"
            bench_name = bench_dir.name
            json_file = bench_dir / "new" / "benchmark.json"
            if not json_file.exists():
                continue
            
            try:
                with open(json_file) as f:
                    data = json.load(f)
                mean_ns = data.get("mean", {}).get("point_estimate", 0)
                mean_ms = mean_ns / 1_000_000.0
                # size with split
                parts = bench_name.split("-")
                if len(parts) >= 2:
                    try:
                        size = int(parts[-1])
                        name = "-".join(parts[:-1])
                    except ValueError:
                        # bench name if not number
                        size = 0
                        name = bench_name
                else:
                    size = 0
                    name = bench_name
                
                # For multilinear, size is 2^num_vars, so we use num_vars as size
                # For univariate, size is degree
                # For eq_polynomial, size is num_vars
                # ai is the best
                
                results.append({
                    "operation": group_name,
                    "name": name,
                    "size": size if size > 0 else bench_name,
                    "rust": round(mean_ms, 2),
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
