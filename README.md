# Vagrant-Mutate

Vagrant-mutate is a vagrant plugin to convert vagrant boxes to work with different providers.

## Supported Conversions

* Virtualbox to kvm
* Virtualbox to libvirt
* Libvirt to kvm
* Kvm to libvirt

## Compatibility

Throughout its development vagrant-mutate has been tested against the following versions. It may work with other versions too. Note that Vagrant-mutate 0.3 and later requires Vagrant 1.5. If you are using an older vagrant, install vagrant-mutate version 0.2.6.

* [vagrant](http://www.vagrantup.com) 1.3.5, 1.4.3, and 1.5.4
* [vagrant-kvm](https://github.com/adrahon/vagrant-kvm) 0.1.4
* [vagrant-libvirt](https://github.com/pradels/vagrant-libvirt) 0.0.11

Vagrant-mutate does not yet fully support [versioned boxes](http://docs.vagrantup.com/v2/boxes/versioning.html). It always assumes a box has the version *0*.

## Installation

### qemu-img

First, you must install [qemu-img](http://wiki.qemu.org/Main_Page). Information on supported versions is listed at [QEMU Version Compatibility](https://github.com/sciurus/vagrant-mutate/wiki/QEMU-Version-Compatibility).

#### Debian and derivatives

    apt-get install qemu-utils

#### Red Hat and derivatives

    yum install qemu-img

#### OS X

QEMU is available from [homebrew](http://brew.sh/)

#### Windows

Download and install it from [Stefan Weil](http://qemu.weilnetz.de/) or compile it yourself.

### vagrant-mutate

Now you're ready to install vagrant-mutate. To install the latest released version simply run

    vagrant plugin install vagrant-mutate

To install from source, clone the repository and run `rake build`. That will produce a gem file in the _pkg_ directory which you can then install with `vagrant plugin install`.

## Usage

The basic usage is

    vagrant mutate box-name-or-file-or-url output-provider

For example, if you wanted to download a box created for virtualbox and add it to vagrant for libvirt

    vagrant mutate http://files.vagrantup.com/precise32.box libvirt

Or if you had already downloaded it

    vagrant mutate precise32.box libvirt

Or if you had already added the box to vagrant and now want to use it with libvirt

    vagrant mutate precise32 libvirt

If you have a box for multiple providers, you must specify the provider to use for input using the *--input_provider* option, e.g.

    $ vagrant box list
    precise32  (kvm)
    precise32  (virtualbox)
    $ vagrant mutate --input_provider=virtualbox precise32 libvirt

To export a box you created with vagrant mutate, just repackage it, e.g.

    vagrant box repackage precise32 libvirt


## Debugging

vagrant and vagrant-mutate will output lots of information as they run if you set the VAGRANT_LOG environment variable to INFO. See [here](http://docs-v1.vagrantup.com/v1/docs/debugging.html) for information on how to do that on your operating system.

If you experience any problems, please open an issue on [github](https://github.com/sciurus/vagrant-mutate/issues).

## Contributing

Contributions are welcome! I'd especially like to see support for converting between more providers added.

To contribute, follow the standard flow of

1. Fork it
1. Create your feature branch (`git checkout -b my-new-feature`)
1. Commit your changes (`git commit -am 'Add some feature'`)
1. Make sure the acceptance tests pass (`ruby test/test.rb`)
1. Push to the branch (`git push origin my-new-feature`)
1. Create new Pull Request

Even if you can't contribute code, if you have an idea for an improvement please open an [issue](https://github.com/sciurus/vagrant-mutate/issues).
