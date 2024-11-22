ethereum_module = import_module("github.com/ethpandaops/ethereum-package/main.star")

MADARA_PORT_ID_RPC = "madara-rpc"

def run(plan, args):
    # run the ethereum (L1) cluster nodes
    ethereum_module_result = ethereum_module.run(plan, args["ethereum"])
    
    # create initial configuration for the Madara bootstrapper (only L1 for now)
    BOOTSTRAP_CONFIG_PATH = "/data/bootstrap_config.json"
    BOOTSTRAP_OUTPUT_PATH = "/data/output.json"
    BOOTSTRAP_CONFIG_TEMPLATE = read_file("./resources/nuggets_bootstrap_config.json.tmpl")
    BOOTSTRAP_CONFIG_FILES = plan.render_templates(
        name="bootstrap-configuration",
        config={
            "bootstrap_config.json": struct(
                template=BOOTSTRAP_CONFIG_TEMPLATE,
                data={
                    "APP_CHAIN_ID": "SN_NUGGETS",
                    "ETH_RPC": ethereum_module_result.all_participants[0].el_context.rpc_http_url,
                    "ETH_PRIV_KEY": "0x{}".format(ethereum_module_result.pre_funded_accounts[0].private_key),
                    "ETH_CHAIN_ID": 125471332751785,
                    "L1_DEPLOYER_ADDRESS": ethereum_module_result.pre_funded_accounts[0].address,
                    "L1_WAIT_TIME": "15",
                }
            ),
        }
    )
    bootstrap_mounted_files = {
        "/data/": BOOTSTRAP_CONFIG_FILES,
    }

    # Start Madara bootstrapper
    madara_bootstrapper = plan.add_service(
        name = "madara-bootstrapper",
        config = ServiceConfig(
            image = "nuggetsltd/madara-bootstrapper:latest",
            entrypoint = [
              "tail",
              "-f",
              "/dev/null",
            ],
            files=bootstrap_mounted_files,
        ),
    )

    # build the command to run the bootstrapper, direct output to devnull and then return the output JSON
    command_setup_l1 = "cargo run -- --mode=setup-l1 --config={} --output-file={} >/dev/null 2>&1 && cat {}".format(BOOTSTRAP_CONFIG_PATH, BOOTSTRAP_OUTPUT_PATH, BOOTSTRAP_OUTPUT_PATH)

    # Wait for the bootstrapper to finish L1 Starknet Appchain bootstrapping
    l1_bootstrap_result = plan.wait(
        service_name = 'madara-bootstrapper',
        recipe = ExecRecipe(
          command = [
            "/bin/sh",
            "-c",
            command_setup_l1
          ],
          extract = {
            "starknet_contract_address": "fromjson | .starknet_contract_address",
            "starknet_contract_implementation_address": "fromjson | .starknet_contract_implementation_address",
          }
        ),
        field = "code",
        assertion = "==",
        target_value = 0,
        timeout = "5m",
        description = "L1 Starknet Appchain Bootstrapping",
    )

    plan.print(l1_bootstrap_result["extract.starknet_contract_address"])

    # TODO: Add "Voyager" block explorer: https://sepolia.voyager.online/
    
