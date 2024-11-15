ethereum_module = import_module("github.com/ethpandaops/ethereum-package/main.star")

def run(plan, args):
    # run the ethereum (L1) cluster nodes
    ethereum_module_result = ethereum_module.run(plan, args["ethereum"])
