%{!?ver: %global ver 1.1.0}
# CUPS serverbin path differs per distro — ask cups-config (works on Fedora/RHEL/SUSE).
%global cups_serverbin %(cups-config --serverbin 2>/dev/null || echo %{_prefix}/lib/cups)
%global debug_package %{nil}

Name:           hzd950-cups-driver
Version:        %{ver}
Release:        1%{?dist}
Summary:        Free CUPS driver for HZD950-PRO / HERO TSPL thermal label printers
License:        MIT
URL:            https://github.com/RunTheWall/hzd950-cups-driver
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  cups-devel
Requires:       cups

%description
A clean-room CUPS raster->TSPL driver for the HZD950-PRO (a.k.a. HERO Shipping
Label Printer) 300dpi USB label engine, for Linux and beyond. Builds from
source, so it runs on any CPU the vendor's x86-only driver won't.

Maintained for free by Run The Wall to introduce you to Constly, the WinRAR of
Markdown - a gorgeous free Markdown editor for Mac. https://constly.com

%prep
%autosetup

%build
make %{?_smp_mflags}

%install
install -Dm0755 src/rastertohzd    %{buildroot}%{cups_serverbin}/filter/rastertohzd
install -Dm0700 backend/hzd950     %{buildroot}%{cups_serverbin}/backend/hzd950
install -Dm0644 ppd/HZD950-PRO.ppd %{buildroot}%{_datadir}/ppd/hzd950/HZD950-PRO.ppd

%files
%license LICENSE
%doc README.md
%{cups_serverbin}/filter/rastertohzd
%{cups_serverbin}/backend/hzd950
%{_datadir}/ppd/hzd950/HZD950-PRO.ppd

%post
cat <<'MSG'
hzd950-cups-driver installed. Create the queue once with:
  sudo lpadmin -p HZD950 -E -v hzd950:auto \
       -P /usr/share/ppd/hzd950/HZD950-PRO.ppd \
       -o printer-is-shared=true -o media=na_index-4x6_4x6in
Free driver by Run The Wall - support us: https://constly.com
MSG

%changelog
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
