ethereum_module = import_module("github.com/ethpandaops/ethereum-package/main.star")

MADARA_PORT_ID_RPC = "madara-rpc"
MADARA_PORT_ID_GW = "madara-gateway"

def run(plan, args):
    # run the ethereum (L1) cluster nodes
    ethereum_module_result = ethereum_module.run(plan, args["ethereum"])
    
    # create initial configuration for the Madara bootstrapper (only L1 for now)
    BOOTSTRAP_CONFIG_PATH = "/data/bootstrap_config.json"
    BOOTSTRAP_OUTPUT_PATH = "/data/output.json"
    BOOTSTRAP_CONFIG_TEMPLATE = read_file("./resources/nuggets_bootstrap_config.json.tmpl")
    BOOTSTRAP_CONFIG_FILES = plan.render_templates(
        name="bootstrap-configuration-l1-only",
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
                    "SEQUENCER_RPC_URL": "http://127.0.0.1:9944",
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

    # Wait for the bootstrapper to finish L1 Starknet Appchain bootstrapping
    bootstrap_result_l1 = plan.wait(
        service_name = 'madara-bootstrapper',
        recipe = ExecRecipe(
          command = [
            "/bin/sh",
            "-c",
            "cargo run -- --mode=setup-l1 --config={} --output-file={} >/dev/null 2>&1 && cat {}".format(BOOTSTRAP_CONFIG_PATH, BOOTSTRAP_OUTPUT_PATH, BOOTSTRAP_OUTPUT_PATH)
          ],
          extract = {
            "starknet_contract_address": "fromjson | .starknet_contract_address",
            "starknet_contract_implementation_address": "fromjson | .starknet_contract_implementation_address",
          }
        ),
        field = "code",
        assertion = "==",
        target_value = 0,
        timeout = "15m",
        description = "L1 Starknet Appchain Bootstrapping",
    )

    plan.remove_service(
      # The service name of the service to be removed.
      # MANDATORY
      name = "madara-bootstrapper",

      # A human friendly description for the end user of the package
      # OPTIONAL (Default: Removing service 'SERVICE_NAME')
      description = "removing Madara bootstrapper service"
  )
    
    # create initial configuration for the Madara sequencer Node
    SEQUENCER_NODE_CONFIG_PATH = "/data/nuggets_chain_config.yaml"
    SEQUENCER_NODE_OUTPUT_PATH = "/data/output.json"
    SEQUENCER_NODE_CONFIG_TEMPLATE = read_file("./resources/nuggets_chain_config.yaml.tmpl")
    SEQUENCER_NODE_CONFIG_FILES = plan.render_templates(
        name="nuggets_chain_config",
        config={
            "nuggets_chain_config.yaml": struct(
                template=SEQUENCER_NODE_CONFIG_TEMPLATE,
                data={
                    "NAME": "madara-sequencer",
                    "CHAIN_ID": "SN_PRIVATE",
                    "ETH_CORE_CONTRACT_ADDRESS": bootstrap_result_l1["extract.starknet_contract_address"],
                }
            ),
        }
    )
    sequencer_node_mounted_files = {
        "/data/": SEQUENCER_NODE_CONFIG_FILES,
    }

    # run madara in bootstrapping mode
    madara_SEQUENCER_node = plan.add_service(
        name = "madara-sequencer-bootstrap-mode",
        config = ServiceConfig(
            # image = "ghcr.io/madara-alliance/madara:latest",
            image = "nuggetsltd/madara:latest",
            ports = {
                MADARA_PORT_ID_RPC: PortSpec(9944),
                MADARA_PORT_ID_GW: PortSpec(8080),
            },
            cmd = [
              "--sequencer",
              "--rpc-cors",
              "*",
              "--rpc-external",
              "--feeder-gateway-enable",
              "--gateway-enable",
              "--gateway-external",
              "--gas-price",
              "0",
              "--blob-gas-price",
              "0",
              # "--rpc-methods",
              # "unsafe",
              "--no-l1-sync",
              "--chain-config-path",
              SEQUENCER_NODE_CONFIG_PATH,
            ],
            files=sequencer_node_mounted_files,
        ),
    )

    # TODO: update the configuration of the Madara bootstrapper to include the sequencer RPC endpoint
    BOOTSTRAP_CONFIG_FILES = plan.render_templates(
        name="bootstrap-configuration-sequencer",
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
                    "SEQUENCER_RPC_URL": "http://{}:{}".format(madara_SEQUENCER_node.ip_address, madara_SEQUENCER_node.ports[MADARA_PORT_ID_RPC].number),
                }
            ),
        }
    )
    bootstrap_mounted_files = {
        "/data/": BOOTSTRAP_CONFIG_FILES,
    }
    madara_SEQUENCER_node = plan.add_service(
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
    

    # Wait for the bootstrapper to finish UDC Starknet Appchain bootstrapping
    bootstrap_result_udc = plan.wait(
        service_name = 'madara-bootstrapper',
        recipe = ExecRecipe(
          command = [
            "/bin/sh",
            "-c",
            "cargo run -- --mode=udc --config={} >/dev/null 2>&1 && cat {}".format(BOOTSTRAP_CONFIG_PATH, BOOTSTRAP_OUTPUT_PATH, BOOTSTRAP_OUTPUT_PATH)
          ]
        ),
        field = "code",
        assertion = "==",
        target_value = 0,
        timeout = "15m",
        description = "UDC Starknet Appchain Bootstrapping",
    )

    # Wait for the bootstrapper to finish UDC Starknet Appchain bootstrapping
    bootstrap_result_eth_bridge = plan.wait(
        service_name = 'madara-bootstrapper',
        recipe = ExecRecipe(
          command = [
            "/bin/sh",
            "-c",
            "cargo run -- --mode=eth-bridge --config={} --output-file={} >/dev/null 2>&1 && cat {}".format(BOOTSTRAP_CONFIG_PATH, BOOTSTRAP_OUTPUT_PATH, BOOTSTRAP_OUTPUT_PATH)
          ],
          extract = {
            "l1_bridge_address": "fromjson | .l1_bridge_address",
            "l2_eth_proxy_address": "fromjson | .l2_eth_proxy_address",
            "l2_eth_bridge_proxy_address": "fromjson | .l2_eth_bridge_proxy_address",
          }
        ),
        field = "code",
        assertion = "==",
        target_value = 0,
        timeout = "15m",
        description = "UDC Starknet Appchain Bootstrapping",
    )

    plan.print(bootstrap_result_eth_bridge)

    # TODO: stop madata-sequencer-bootstrap-mode


    # TODO: Add "Voyager" block explorer: https://sepolia.voyager.online/
    
