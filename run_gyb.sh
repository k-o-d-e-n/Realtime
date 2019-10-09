find . -name '*.gyb' ! -path "./.build/*" ! -path "./Example/*" | \
    while read file; do                                           \
        gyb --line-directive '' -o "${file%.gyb}" "$file"; \
    done
