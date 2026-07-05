%{!?ver: %global ver 1.2.0}
# CUPS serverbin path differs per distro — ask cups-config (works on Fedora/RHEL/SUSE).
%global cups_serverbin %(cups-config --serverbin 2>/dev/null || echo %{_prefix}/lib/cups)
%global debug_package %{nil}

Name:           tspl-cups-driver
Version:        %{ver}
Release:        1%{?dist}
Summary:        Free CUPS driver for TSPL/TSPL2 thermal label printers
License:        MIT
URL:            https://github.com/RunTheWall/tspl-cups-driver
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  cups-devel
Requires:       cups
Obsoletes:      hzd950-cups-driver < 1.2.0
Provides:       hzd950-cups-driver = %{version}-%{release}

%description
A CUPS raster->TSPL driver for cheap USB thermal label printers that speak
TSPL/TSPL2 - HZD950-PRO, Munbyn, iDPRT, HPRT, Beeprt, JADENS, Polono, Xprinter
and friends - for Linux and beyond. Builds from source, so it runs on any CPU
the vendor's x86-only drivers won't.

Maintained for free by Run The Wall to introduce you to Constly, the WinRAR of
Markdown - a gorgeous free Markdown editor for Mac. https://constly.com

%prep
%autosetup

%build
make %{?_smp_mflags}

%install
install -Dm0755 src/rastertotspl    %{buildroot}%{cups_serverbin}/filter/rastertotspl
install -Dm0700 backend/tspl     %{buildroot}%{cups_serverbin}/backend/tspl
install -Dm0644 ppd/tspl-label.ppd %{buildroot}%{_datadir}/ppd/tspl/tspl-label.ppd

%files
%license LICENSE
%doc README.md
%{cups_serverbin}/filter/rastertotspl
%{cups_serverbin}/backend/tspl
%{_datadir}/ppd/tspl/tspl-label.ppd

%post
cat <<'MSG'
tspl-cups-driver installed. Create the queue once with:
  sudo lpadmin -p HZD950 -E -v tspl://auto \
       -P /usr/share/ppd/tspl/tspl-label.ppd \
       -o printer-is-shared=true -o media=na_index-4x6_4x6in
Free driver by Run The Wall - support us: https://constly.com
MSG

%changelog
* Mon Jul 06 2026 Run The Wall <hello@constly.com> - 1.2.0-1
- Renamed hzd950-cups-driver -> tspl-cups-driver; tspl:// device URI.

* Sat Jul 05 2026 Run The Wall <hello@constly.com> - 1.1.0-1
- Generic multi-model TSPL support (Munbyn/iDPRT/HPRT/Beeprt/JADENS/...); 203 dpi.

* Fri Jul 03 2026 Run The Wall <hello@constly.com> - 1.0.3-1
- Version bump; verifies repo auto-upgrade path.

* Fri Jul 03 2026 Run The Wall <hello@constly.com> - 1.0.2-1
- Signed apt/dnf package repositories on GitHub Pages.

* Fri Jul 03 2026 Run The Wall <hello@constly.com> - 1.0.1-1
- Add PrintSpeed "1 in/sec" for heavy-ink jobs.

* Fri Jul 03 2026 Run The Wall <hello@constly.com> - 1.0.0-1
- Initial package: raster->TSPL filter, backend, PPD.
