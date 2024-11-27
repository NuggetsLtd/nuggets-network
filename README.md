# Nuggets Network
This repo sets up Nuggets Private Blockchain Network, for use with local development & CI environments

## Pre-Requisites

- Install Kurtosis: https://docs.kurtosis.com/install/

## Quick-Start
Copy the `.package_args.yaml` file to `package_args.yaml`, and add in your configuration settings (specifically Infura API key).

*NOTE*: Due to an issue with starting up the latest Madara docker image package, you'll need to pull the repo and build the container locally to get this package to run correctly at the moment.

```sh
# clone the madara repo to somewhere on your machine
git clone https://github.com/madara-alliance/madara.git
# change directory to `madara`
cd madara
# build the madara docker image on your machine
docker build -t nuggetsltd/madara .
```

In your local terminal run:
```bash
./start.sh
```
This will run:

1. Madara Sequencer
2. Madara Full Node(s)
