# World Data Validation

The world model is now large enough that consistency cannot rely on memory. `tools/validate_world_data.py` performs a standard-library structural pass over world JSON and validates critical commodity, ship-class and manufacturer references.

The reference-contract file documents foreign-key expectations. Validation should expand whenever a new mechanics-facing dataset introduces stable-ID references. Broken mechanics references are errors; incomplete graph unification can remain warnings while draft data is being expanded.

The final design principle is simple: density is useful only when the layers agree with one another.
