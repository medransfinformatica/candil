#!/usr/bin/env bash
# ============================================================
#   CANDIL OS - Lanzador de la suite local (Linux / macOS)
#   Uso:  ./start-candil.sh [serve|dev|build|static|stop|status]
#   Por defecto: serve  (deja las 7 apps en linea: sirve los dist al instante y
#                        compila solo lo que falte)
#
#   La suite no es uniforme; cada repo usa su runner web:
#     trunk -> PhotoCraft, VectorCraft, DesignCraft, PdfCraft
#     xtask -> FilmCraft, LightCraft, EffectCraft (`cargo xtask web --serve`)
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$ROOT/_run"
ROUTER="$ROOT/tools/candil-router.php"
MODE="${1:-serve}"
mkdir -p "$RUN"

FOLDERS=(photocraft vectorcraft filmcraft lightcraft effectcraft designcraft pdfcraft)
NAMES=("El Retrato" "El Cincel" "La Tijera" "El Farol" "La Chispa" "La Imprenta" "El Folleto")
PORTS=(8081 8082 8083 8084 8085 8086 8087)
RUNNERS=(trunk trunk xtask xtask xtask trunk trunk)
WEBS=("photocraft/apps/photocraft-web" "vectorcraft/apps/vectorcraft-web" "filmcraft" "lightcraft" "effectcraft" "designcraft/apps/designcraft-web" "pdfcraft/apps/pdfcraft-web")
DISTS=("photocraft/dist/web" "vectorcraft/dist/web" "filmcraft/target/web/dist" "lightcraft/target/web-site" "effectcraft/target/web/dist" "designcraft/dist/web" "pdfcraft/dist/web")

Y='\033[33m'; G='\033[32m'; R='\033[31m'; D='\033[90m'; N='\033[0m'
head() { echo; echo -e "${Y}============================================================${N}"; \
         echo -e "${Y}  C A N D I L   O S  -  Herramientas Criollas${N}"; \
         echo -e "${Y}  Modo: $MODE    Raiz: $ROOT${N}"; \
         echo -e "${Y}============================================================${N}"; echo; }

have()       { command -v "$1" >/dev/null 2>&1; }
get_cargo()  { if have cargo; then echo cargo; else echo "$HOME/.cargo/bin/cargo"; fi; }
have_trunk() { have trunk || [ -x "$HOME/.cargo/bin/trunk" ]; }
get_trunk()  { if have trunk; then echo trunk; else echo "$HOME/.cargo/bin/trunk"; fi; }
have_php()   { have php; }
have_py()    { have python3 || have python; }
get_py()     { if have python3; then echo python3; else echo python; fi; }

port_up() { if have nc; then nc -z 127.0.0.1 "$1" >/dev/null 2>&1; return $?; fi
            (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }
port_pid() { have lsof && lsof -ti TCP:"$1" -sTCP:LISTEN 2>/dev/null | head -n1; }

prereq_help() {
  echo -e "${R}[!] Falta la cadena de compilacion WebAssembly.${N}"; echo
  echo "    Requisitos:"
  echo "      - Rust 1.95+                https://rustup.rs"
  echo "      - rustup target add wasm32-unknown-unknown"
  echo "      - cargo install --locked trunk   (Photo/Vector/Design/PdfCraft)"
  echo "      - wasm-bindgen-cli 0.2.129       (Film/Light/EffectCraft)"
  echo
  echo "    Sin toolchain, serví sitios ya compilados: ./start-candil.sh static"; echo
}

start_tool() { # i
  local i="$1" folder="${FOLDERS[$i]}" port="${PORTS[$i]}" name="${NAMES[$i]}" runner="${RUNNERS[$i]}"
  local log="$RUN/$folder.log" work="$ROOT/${WEBS[$i]}"
  if [ ! -d "$work" ]; then echo -e "  ${R}[x] $name: falta $work${N}"; return; fi
  if [ "$runner" = "trunk" ]; then
    ( cd "$work" && nohup "$(get_trunk)" serve --release --port "$port" --address 127.0.0.1 >"$log" 2>&1 & echo $! >>"$RUN/pids" )
  else
    ( cd "$work" && nohup "$(get_cargo)" xtask web --serve "$port" >"$log" 2>&1 & echo $! >>"$RUN/pids" )
  fi
  echo -e "  ${G}[>] $(printf '%-12s' "$name") -> http://localhost:$port   ($runner; log: _run/$folder.log)${N}"
}

start_static() { # i
  local i="$1" name="${NAMES[$i]}" port="${PORTS[$i]}" dist="$ROOT/${DISTS[$i]}" log="$RUN/${FOLDERS[$i]}.log"
  if port_up "$port"; then echo -e "  ${G}[=] $(printf '%-12s' "$name") -> http://localhost:$port   (ya en linea)${N}"; return; fi
  if [ ! -f "$dist/index.html" ]; then
    echo -e "  ${D}[.] $(printf '%-12s' "$name") sin compilar - corré: ./start-candil.sh build${N}"; return
  fi
  if have_php; then
    ( cd "$dist" && nohup php -S "127.0.0.1:$port" -t "$dist" "$ROUTER" >"$log" 2>&1 & echo $! >>"$RUN/pids" )
  elif have_py; then
    ( cd "$dist" && nohup "$(get_py)" -m http.server "$port" --bind 127.0.0.1 >"$log" 2>&1 & echo $! >>"$RUN/pids" )
  else
    echo -e "  ${R}[x] $name: necesito php o python3 para servir ${DISTS[$i]}${N}"; return
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 0.2; port_up "$port" && break; done
  if port_up "$port"; then
    echo -e "  ${G}[>] $(printf '%-12s' "$name") -> http://localhost:$port   (estatico, ${DISTS[$i]})${N}"
  else
    echo -e "  ${R}[x] $(printf '%-12s' "$name") no respondio en :$port   (ver _run/${FOLDERS[$i]}.log)${N}"
  fi
}

head

case "$MODE" in
  stop)
    echo "  Deteniendo servicios en los puertos 8081-8087..."
    if [ -f "$RUN/pids" ]; then
      while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null && echo -e "  ${Y}[x] PID $pid detenido${N}"; done <"$RUN/pids"
      rm -f "$RUN/pids"
    fi
    for p in "${PORTS[@]}"; do pid="$(port_pid "$p")"; [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null && echo -e "  ${Y}[x] puerto $p (PID $pid) detenido${N}"; done
    ;;

  status)
    echo "  Estado de las herramientas:"
    on=0
    for i in "${!PORTS[@]}"; do
      if port_up "${PORTS[$i]}"; then on=$((on+1)); echo -e "    ${G}$(printf '%-12s' "${NAMES[$i]}") :${PORTS[$i]}  EN LINEA  [${RUNNERS[$i]}]${N}"; \
      else echo -e "    ${D}$(printf '%-12s' "${NAMES[$i]}") :${PORTS[$i]}  apagado  [${RUNNERS[$i]}]${N}"; fi
    done
    echo; echo -e "  ${Y}$on de ${#PORTS[@]} en linea.${N}"
    ;;

  build)
    if ! have_trunk && ! have cargo; then prereq_help; exit 1; fi
    echo "  Compilando cada app..."
    for i in "${!FOLDERS[@]}"; do
      folder="${FOLDERS[$i]}"; runner="${RUNNERS[$i]}"; work="$ROOT/${WEBS[$i]}"
      echo; echo -e "  ${Y}== ${NAMES[$i]} ($folder) [$runner] ==${N}"
      [ ! -d "$work" ] && { echo -e "     ${R}falta el directorio${N}"; continue; }
      if [ "$runner" = "trunk" ]; then
        have_trunk || { echo -e "     ${R}sin trunk, se salta${N}"; continue; }
        ( cd "$work" && "$(get_trunk)" build --release ) || echo -e "     ${R}fallo${N}"
      else
        ( cd "$work" && "$(get_cargo)" xtask web ) || echo -e "     ${R}fallo${N}"
      fi
    done
    ;;

  static)
    if ! have_php && ! have_py; then echo -e "${R}[!] Necesito php o python3 para el modo static.${N}"; exit 1; fi
    echo "  Sirviendo sitios compilados..."
    for i in "${!FOLDERS[@]}"; do start_static "$i"; done
    ;;

  dev)
    if ! have_trunk && ! have cargo; then prereq_help; exit 1; fi
    echo "  Arrancando servidores de desarrollo (recompila; puede tardar)..."
    for i in "${!FOLDERS[@]}"; do start_tool "$i"; done
    ;;

  *)
    echo "  Dejando la suite en linea (8081-8087); los dist ya compilados se sirven al instante..."
    for i in "${!FOLDERS[@]}"; do
      dist="$ROOT/${DISTS[$i]}"
      if { have_php || have_py; } && [ -f "$dist/index.html" ]; then start_static "$i"
      elif have_trunk || have cargo; then start_tool "$i"
      else echo -e "  ${R}[x] ${NAMES[$i]}: falta el dist compilado y el toolchain${N}"; fi
    done
    ;;
esac

echo
echo -e "  Panel CANDIL OS: ${Y}http://localhost/candil/candil-suite/index.html${N}"
echo
