# displaylink-minimal

DisplayLink driver installer for Debian Testing (might work on other versions and other Debian based distributions) which uses the open source and Debian packaged EVDI kernel module and does not execute DisplayLink's installer scripts (except for extracting the file contents).

## Installation

1. Download the [DisplayLink USB Graphics Software for Ubuntu](https://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu) (standalone installer)
2. Clone this repoistory
```shell
git clone https://github.com/lusor/displaylink-minimal.git
```
3. Start the installation
```shell
<path_to_displaylink-minimal>/displaylink.sh <DisplayLinkSoftware>
```

## Uninstall

```shell
<path_to_displaylink-minimal>/displaylink.sh --uninstall
```

## Credits

This work was heavily inspired by [displaylink-debian](https://github.com/AdnanHodzic/displaylink-debian) by [Adnan Hodzic](https://github.com/AdnanHodzic), thank you very much!
