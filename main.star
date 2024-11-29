ethereum_module = import_module("github.com/ethpandaops/ethereum-package/main.star")

MADARA_PORT_ID_RPC = "madara-rpc"
MADARA_PORT_ID_GW = "madara-gateway"
MADARA_FULL_NODE_PREFIX = "madara-full-"

def run(plan, args):
    APP_CHAIN_NAME = args["starknet"]["app_chain_name"]
    APP_CHAIN_ID = args["starknet"]["app_chain_id"]
    NATIVE_FEE_TOKEN_ADDRESS = args["starknet"]["native_fee_token_address"]
    PARENT_FEE_TOKEN_ADDRESS = args["starknet"]["parent_fee_token_address"]
    ETH_CORE_CONTRACT_ADDRESS = args["starknet"]["eth_core_contract_address"]
    ETH_GPS_STATEMENT_VERIFIER = args["starknet"]["eth_gps_statement_verifier"]
    SEQUENCER_ADDRESS = args["starknet"]["sequencer_address"]
    
    # create configuration for Madara sequencer Node
    MADARA_NODE_CONFIG_PATH = "/data/madara_app_chain_config.yaml"
    MADARA_NODE_CONFIG_TEMPLATE = read_file("./resources/madara_app_chain_config.yaml.tmpl")
    SEQUENCER_NODE_CONFIG_FILES = plan.render_templates(
        name="madara_sequencer_chain_config",
        config={
            "madara_app_chain_config.yaml": struct(
                template=MADARA_NODE_CONFIG_TEMPLATE,
                data={
                    "NAME": APP_CHAIN_NAME,
                    "CHAIN_ID": APP_CHAIN_ID,
                    "NATIVE_FEE_TOKEN_ADDRESS": NATIVE_FEE_TOKEN_ADDRESS,
                    "PARENT_FEE_TOKEN_ADDRESS": PARENT_FEE_TOKEN_ADDRESS,
                    "ETH_CORE_CONTRACT_ADDRESS": ETH_CORE_CONTRACT_ADDRESS,
                    "ETH_GPS_STATEMENT_VERIFIER": ETH_GPS_STATEMENT_VERIFIER,
                    "SEQUENCER_ADDRESS": SEQUENCER_ADDRESS,
                }
            ),
        }
    )
    sequencer_node_mounted_files = {
        "/data/": SEQUENCER_NODE_CONFIG_FILES,
    }

    # get the Ethereum network and API key info
    NETWORK = args["starknet"]["network"]
    INFURA_API_KEY = args["starknet"]["infura_api_key"]
    L1_RPC_ENDPOINT = "https://{}.infura.io/v3/{}".format(NETWORK, INFURA_API_KEY)
    ETH_CHAIN_ID = args["ethereum"]["eth_chain_id"]
    ETH_PRIV_KEY = args["ethereum"]["eth_private_key"]

    # Start Madara sequencer node
    #   Chain Configuration: https://docs.madara.build/chain-configuration/parameters
    madara_sequencer_node = plan.add_service(
        name = "madara-sequencer",
        config = ServiceConfig(
            image = "ghcr.io/madara-alliance/madara:latest",
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
              "--chain-config-path",
              MADARA_NODE_CONFIG_PATH,
              "--l1-endpoint",
              "https://{}.infura.io/v3/{}".format(NETWORK, INFURA_API_KEY),
            ],
            files=sequencer_node_mounted_files,
        ),
    )

    # get the number of Madara full nodes to run
    FULL_NODE_COUNT = args["starknet"]["full_node_count"]

    # Simple check to verify that we have at least 1 node in our cluster
    if FULL_NODE_COUNT == 0:
       fail("Need at least 1 node to Start Starknet cluster got 0")

    # create configuration for Madara full Node(s)
    FULL_NODE_CONFIG_FILES = plan.render_templates(
        name="madara_full_chain_config",
        config={
            "madara_app_chain_config.yaml": struct(
                template=MADARA_NODE_CONFIG_TEMPLATE,
                data={
                    "CHAIN_NAME": APP_CHAIN_NAME,
                    "CHAIN_ID": APP_CHAIN_ID,
                    "FEEDER_GATEWAY_URL": "http://{}:{}/feeder_gateway/".format(madara_sequencer_node.ip_address, madara_sequencer_node.ports[MADARA_PORT_ID_GW].number),
                    "GATEWAY_URL": "http://{}:{}/gateway/".format(madara_sequencer_node.ip_address, madara_sequencer_node.ports[MADARA_PORT_ID_GW].number),
                    "NATIVE_FEE_TOKEN_ADDRESS": NATIVE_FEE_TOKEN_ADDRESS,
                    "PARENT_FEE_TOKEN_ADDRESS": PARENT_FEE_TOKEN_ADDRESS,
                    "ETH_CORE_CONTRACT_ADDRESS": ETH_CORE_CONTRACT_ADDRESS,
                    "ETH_GPS_STATEMENT_VERIFIER": ETH_GPS_STATEMENT_VERIFIER,
                    "SEQUENCER_ADDRESS": "0x0", # Full node sequencer address is 0x0
                }
            ),
        }
    )
    full_node_mounted_files = {
        "/data/": FULL_NODE_CONFIG_FILES,
    }

    # Iteratively add each Madara *full* node to the cluster, with the given names and serviceConfig specified below
    for node in range(0, FULL_NODE_COUNT):
       node_name = get_madara_full_node_service_name(node)
       plan.print("Adding Madara full node: {}".format(node_name))
       config = get_madara_full_node_service_config(MADARA_NODE_CONFIG_PATH, L1_RPC_ENDPOINT, SEQUENCER_ADDRESS, full_node_mounted_files)
       plan.add_service(name = node_name, config = config)
    

    BOOTSTRAP_CONFIG_PATH = "/data/bootstrap_config.json"
    BOOTSTRAP_OUTPUT_PATH = "/data/output.json"
    ROLLUP_SEQUENCER_URL = "http://{}:{}".format(madara_sequencer_node.ip_address, madara_sequencer_node.ports[MADARA_PORT_ID_RPC].number)

    bootstrapper_config = get_madara_bootstrapper_config(plan, APP_CHAIN_ID, L1_RPC_ENDPOINT, ETH_CHAIN_ID, ETH_PRIV_KEY, ROLLUP_SEQUENCER_URL, NATIVE_FEE_TOKEN_ADDRESS, PARENT_FEE_TOKEN_ADDRESS, ETH_CORE_CONTRACT_ADDRESS)

    madara_bootstrapper = plan.add_service(
        name = "madara-bootstrapper",
        config = bootstrapper_config,
    )

    # TODO: get the bootstrapper to run command successfully
    # # build the command to run the bootstrapper, direct output to devnull and then return the output JSON
    # #   modes: core, setup-l1, setup-l2, eth-bridge, erc20-bridge, udc, argent, braavos
    # # command_setup_l1 = "cargo run -- --mode=setup-l2 --config={} --output-file={} >/dev/null 2>&1 && cat {}".format(BOOTSTRAP_CONFIG_PATH, BOOTSTRAP_OUTPUT_PATH, BOOTSTRAP_OUTPUT_PATH)
    # command_setup_l1 = "cargo run -- --mode=setup-l2 --config={} --output-file={}".format(BOOTSTRAP_CONFIG_PATH, BOOTSTRAP_OUTPUT_PATH, BOOTSTRAP_OUTPUT_PATH)

    # # Wait for the bootstrapper to finish L1 Starknet Appchain bootstrapping
    # l1_bootstrap_result = plan.wait(
    #     service_name = 'madara-bootstrapper',
    #     recipe = ExecRecipe(
    #       command = [
    #         "/bin/sh",
    #         "-c",
    #         command_setup_l1
    #       ],
    #       # extract = {
    #       #   "starknet_contract_address": "fromjson | .starknet_contract_address",
    #       #   "starknet_contract_implementation_address": "fromjson | .starknet_contract_implementation_address",
    #       # }
    #     ),
    #     field = "code",
    #     assertion = "==",
    #     target_value = 0,
    #     timeout = "5m",
    #     description = "Braavos Appchain Bootstrapping",
    # )

    # plan.print(l1_bootstrap_result)

    # TODO: Add "Voyager" block explorer: https://sepolia.voyager.online/
    

def get_madara_full_node_service_name(node_idx):
    return MADARA_FULL_NODE_PREFIX + str(node_idx)

def get_madara_full_node_service_config(config_path, l1_rpc_endpoint, sequencer_address, mounted_files):
    return ServiceConfig(
        # image = "ghcr.io/madara-alliance/madara:latest",
        image = "nuggetsltd/madara:latest",
        ports = {
            MADARA_PORT_ID_RPC: PortSpec(9944),
        },
        cmd = [ 
          "--full",
          "--rpc-cors",
          "*",
          "--rpc-external",
          "--chain-config-path",
          config_path,
          "--l1-endpoint",
          l1_rpc_endpoint,
        ],
        files=mounted_files,
    )

def get_madara_bootstrapper_config(plan, app_chain_id, eth_rpc, eth_chain_id, eth_private_key, rollup_sequencer_url, native_fee_token_address, parent_fee_token_address, eth_core_contract_address):
    # create configuration for the Madara bootstrapper
    BOOTSTRAP_CONFIG_TEMPLATE = read_file("./resources/nuggets_bootstrap_config.json.tmpl")
    BOOTSTRAP_CONFIG_FILES = plan.render_templates(
        name="bootstrap-configuration",
        config={
            "bootstrap_config.json": struct(
                template=BOOTSTRAP_CONFIG_TEMPLATE,
                data={
                    "APP_CHAIN_ID": app_chain_id,
                    "ROLLUP_SEQUENCER_URL": rollup_sequencer_url,
                    "ETH_RPC": eth_rpc,
                    "ETH_PRIV_KEY": eth_private_key,
                    "ETH_CHAIN_ID": eth_chain_id,
                    "ETH_CORE_CONTRACT_ADDRESS": eth_core_contract_address,
                    "L1_DEPLOYER_ADDRESS": "",
                    "L1_WAIT_TIME": "15",
                    "NATIVE_FEE_TOKEN_ADDRESS": native_fee_token_address,
                    "PARENT_FEE_TOKEN_ADDRESS": parent_fee_token_address,
                }
            ),
        }
    )
    bootstrap_mounted_files = {
        "/data/": BOOTSTRAP_CONFIG_FILES,
    }

    return ServiceConfig(
        image = "nuggetsltd/madara-bootstrapper:latest",
        entrypoint = [
          "tail",
          "-f",
          "/dev/null",
        ],
        files=bootstrap_mounted_files,
    )
