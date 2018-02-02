# Test Build

Scripts to test the building of packages in the archive for a particular release.


## Replicating Results

To aid in reproducing my results the following lays out the process used for building packages:

```
apt-get update
apt-get install -y ubuntu-dev-tools
pull-lp-source $PACKAGE $RELEASE
apt-get build-dep $PACKAGE
cd $PACKAGE-*/
dpkg-buildpackage -j4 -us -uc
```
