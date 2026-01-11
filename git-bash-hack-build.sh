#!/bin/bash
# git-bash-hack-build.sh


#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" ) '

set -euo pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
scriptDir="$(command dirname -- "${scriptName}")"
[[ -n "${DEBUGSH:-}" ]] && set -x

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

# Detect bash version
check_bash_version() {
    local bash_ver="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    echo "Detected Bash version: $BASH_VERSION"
    
    if [[ ! $BASH_VERSION =~ ^5\. ]]; then
        die "bashdb requires Bash 5.x, but you have $BASH_VERSION"
    fi
    echo "✓ Bash version OK (5.x required)"
}

# Substitute variables in a .in file
substitute_file() {
    local infile="$1"
    local outfile="$2"
    
    echo "Processing: $infile -> $outfile"
    
    sed \
        -e "s|@SH_PROG@|$SH_PROG|g" \
        -e "s|@PACKAGE@|$PACKAGE|g" \
        -e "s|@PACKAGE_VERSION@|$PACKAGE_VERSION|g" \
        -e "s|@prefix@|$PREFIX|g" \
        -e "s|@PKGDATADIR@|$PKGDATADIR|g" \
        -e "s|@BASHDB_MAIN@|$BASHDB_MAIN|g" \
        -e "s|@DBGR_MAIN@|$BASHDB_MAIN|g" \
        "$infile" > "$outfile"
    
    chmod +x "$outfile"
}

main() {
    cd "$scriptDir" || die "Cannot cd to $scriptDir"
    
    echo "========================================"
    echo "bashdb git-bash hack builder"
    echo "========================================"
    
    check_bash_version
    
    # Configuration variables (from configure.ac)
    PACKAGE="bashdb"
    OK_BASH_VERS="5.2"
    RELSTATUS="1.2.0"
    PACKAGE_VERSION="${OK_BASH_VERS}-${RELSTATUS}"
    
    # Find bash executable
    SH_PROG="${SH_PROG:-$(command -v bash)}"
    echo "Using bash: $SH_PROG"
    
    # Installation to ~/.local following XDG conventions
    # User can override with PREFIX env var
    if [[ -z "${PREFIX:-}" ]]; then
        PREFIX="${HOME}/.local"
    fi
    
    BINDIR="${PREFIX}/bin"
    # Put library files in bashdb.d subdirectory to avoid polluting bin/
    PKGDATADIR="${BINDIR}/bashdb.d"
    BASHDB_MAIN="${PKGDATADIR}/bashdb-main.inc"
    
    echo ""
    echo "Configuration:"
    echo "  PREFIX      = $PREFIX"
    echo "  BINDIR      = $BINDIR"
    echo "  PKGDATADIR  = $PKGDATADIR"
    echo "  BASHDB_MAIN = $BASHDB_MAIN"
    echo ""
    echo "Installation layout:"
    echo "  Executable:  ${BINDIR}/bashdb"
    echo "  Libraries:   ${PKGDATADIR}/"
    echo ""
    echo "Note: Library files go in bashdb.d/ to keep ${BINDIR} clean"
    echo ""
    
    # Ask for confirmation
    read -p "Proceed with installation? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Create directory structure
    echo ""
    echo "Creating directory structure..."
    mkdir -p "${PREFIX}/bin"
    mkdir -p "${PKGDATADIR}/command/info_sub"
    mkdir -p "${PKGDATADIR}/command/set_sub"
    mkdir -p "${PKGDATADIR}/command/show_sub"
    mkdir -p "${PKGDATADIR}/init"
    mkdir -p "${PKGDATADIR}/lib"
    mkdir -p "${PKGDATADIR}/data"
    
    # Process .in files
    echo ""
    echo "Processing template files..."
    substitute_file "bashdb.in" "${BINDIR}/bashdb"
    substitute_file "bashdb-trace.in" "${PKGDATADIR}/bashdb-trace"
    substitute_file "bashdb-main.inc.in" "${PKGDATADIR}/bashdb-main.inc"
    
    # Copy shell library files (these don't need substitution)
    echo ""
    echo "Copying library files..."
    
    cp -v dbg-main.sh "${PKGDATADIR}/"
    cp -v set-d-vars.sh "${PKGDATADIR}/"
    cp -v bashdb-part2.sh "${PKGDATADIR}/"
    cp -v getopts_long.sh "${PKGDATADIR}/"
    
    # Copy command files
    echo ""
    echo "Copying command files..."
    cp -v command/*.sh "${PKGDATADIR}/command/"
    [[ -d command/info_sub ]] && cp -v command/info_sub/*.sh "${PKGDATADIR}/command/info_sub/" 2>/dev/null || true
    [[ -d command/set_sub ]] && cp -v command/set_sub/*.sh "${PKGDATADIR}/command/set_sub/" 2>/dev/null || true
    [[ -d command/show_sub ]] && cp -v command/show_sub/*.sh "${PKGDATADIR}/command/show_sub/" 2>/dev/null || true
    
    # Copy init files
    echo ""
    echo "Copying init files..."
    cp -v init/*.sh "${PKGDATADIR}/init/"
    
    # Copy lib files
    echo ""
    echo "Copying lib files..."
    cp -v lib/*.sh "${PKGDATADIR}/lib/"
    [[ -f lib/term-highlight.py ]] && cp -v lib/term-highlight.py "${PKGDATADIR}/lib/" || true
    
    # Copy data files
    echo ""
    echo "Copying data files..."
    [[ -d data ]] && cp -v data/*.sh "${PKGDATADIR}/data/" 2>/dev/null || true
    
    echo ""
    echo "========================================"
    echo "✓ Installation complete!"
    echo "========================================"
    echo ""
    echo "Installed to: $PREFIX"
    echo ""
    
    # Check if BINDIR is in PATH
    if [[ ":$PATH:" == *":${BINDIR}:"* ]]; then
        echo "✓ ${BINDIR} is already in your PATH"
        echo ""
        echo "You can now run: bashdb -- your-script.sh"
    else
        echo "⚠ ${BINDIR} is NOT in your PATH"
        echo ""
        echo "To add it, add this to your ~/.bashrc or ~/.bash_profile:"
        echo "  export PATH=\"${BINDIR}:\$PATH\""
        echo ""
        echo "Or run directly: ${BINDIR}/bashdb -- your-script.sh"
    fi
    echo ""
    echo "Test with: bashdb --version"
    echo ""
    
    # Verify installation
    if [[ -x "${BINDIR}/bashdb" ]]; then
        echo "Testing installation..."
        "${BINDIR}/bashdb" --version 2>&1 || echo "Warning: version check failed"
    fi
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    builtin exit
fi
command true

