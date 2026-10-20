"""Reuse the dependency reader, keep replacement evidence separate from ice."""
import source_binding

source_binding.OUT = source_binding.ROOT / "build/qa/spell-replacement-20261018"
if __name__ == "__main__":
    raise SystemExit(source_binding.main())
