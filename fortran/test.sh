set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
echo "start building..."
cd "$BUILD_DIR"
make clean
make
echo ""
echo "rust test with f feature..."
cd "$PROJECT_ROOT"
export LD_LIBRARY_PATH="$BUILD_DIR:$LD_LIBRARY_PATH"
cargo test --features fortran --lib fortran::integration_test -- --nocapture

echo ""
echo "All tests passed"

