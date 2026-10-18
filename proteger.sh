
#!/usr/bin/env bash

set -Eeuo pipefail

DIR="/home/andre/codes/DazeGhost"
SCRIPT="$DIR/script.lua"
CAOS="$DIR/caos.lua"
OUTPUT="$DIR/protegido.lua"
EXECUTABLE="$DIR/dazeghost"

BACKUP_DIR=""
SUCCESS=0

cleanup() {
    local status=$?

    trap - EXIT INT TERM

    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        if [[ -f "$BACKUP_DIR/script.lua" ]]; then
            cp -f "$BACKUP_DIR/script.lua" "$SCRIPT" || status=1
        fi

        if [[ -f "$BACKUP_DIR/caos.lua" ]]; then
            cp -f "$BACKUP_DIR/caos.lua" "$CAOS" || status=1
        fi

        rm -rf -- "$BACKUP_DIR"
    fi

    if [[ "$SUCCESS" -eq 1 && "$status" -eq 0 ]]; then
        printf '\nOfuscação concluída com sucesso.\n'
        printf 'Arquivo final: %s\n' "$OUTPUT"
        printf 'Arquivos originais restaurados.\n'
    else
        printf '\nProcesso interrompido ou finalizado com erro.\n' >&2
    fi

    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$DIR"

for file in "$SCRIPT" "$CAOS" "$EXECUTABLE"; do
    if [[ ! -f "$file" ]]; then
        printf 'Arquivo não encontrado: %s\n' "$file" >&2
        exit 1
    fi
done

if [[ ! -x "$EXECUTABLE" ]]; then
    printf 'Executável sem permissão: %s\n' "$EXECUTABLE" >&2
    exit 1
fi

BACKUP_DIR=$(mktemp -d "$DIR/.dazeghost-backup.XXXXXXXX")

cp -p "$SCRIPT" "$BACKUP_DIR/script.lua"
cp -p "$CAOS" "$BACKUP_DIR/caos.lua"

protect() {
    local stage="$1"

    printf '\nExecutando ofuscação %s/4...\n' "$stage"

    "$EXECUTABLE" \
        --obfuscate \
        --preset strong \
        --name-generator random \
        --anti-ia \
        --anti-tamper \
        --watermark "DazeGhost-Protected" \
        --rounds 5 \
        --density 100 \
        --noise-density 100 \
        --mode bytecode \
        --runtime auto \
        --min-chunk-size 1 \
        --max-chunk-size 4096 \
        --compress \
        --max-output-bytes 134217728 \
        --max-intermediate-bytes 536870912 \
        --input "$SCRIPT" \
        --decoy "$CAOS" \
        --output "$OUTPUT"

    if [[ ! -s "$OUTPUT" ]]; then
        printf 'Saída inválida na etapa %s.\n' "$stage" >&2
        return 1
    fi

    printf 'Etapa %s concluída.\n' "$stage"
}

protect 1

cp -f "$OUTPUT" "$SCRIPT"

protect 2

cp -f "$OUTPUT" "$CAOS"

protect 3

cp -f "$OUTPUT" "$SCRIPT"
cp -f "$OUTPUT" "$CAOS"

protect 4

SUCCESS=1
