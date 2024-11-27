ethereum_module = import_module("github.com/ethpandaops/ethereum-package/main.star")

MADARA_PORT_ID_RPC = "madara-rpc"
MADARA_PORT_ID_GW = "madara-gateway"
MADARA_FULL_NODE_PREFIX = "madara-full-"

def run(plan, args):
    CHAIN_NAME = args["starknet"]["chain_name"]
    CHAIN_ID = args["starknet"]["chain_id"]
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
                    "NAME": CHAIN_NAME,
                    "CHAIN_ID": CHAIN_ID,
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

    # get the Ethereum network and API key
    NETWORK = args["starknet"]["network"]
    API_KEY = args["starknet"]["infura_api_key"]

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
              "https://{}.infura.io/v3/{}".format(NETWORK, API_KEY),
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
                    "CHAIN_NAME": CHAIN_NAME,
                    "CHAIN_ID": CHAIN_ID,
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
       config = get_madara_full_node_service_config(MADARA_NODE_CONFIG_PATH, NETWORK, API_KEY, SEQUENCER_ADDRESS, full_node_mounted_files)
       plan.add_service(name = node_name, config = config)

    # TODO: Add "Voyager" block explorer: https://sepolia.voyager.online/
    

def get_madara_full_node_service_name(node_idx):
    return MADARA_FULL_NODE_PREFIX + str(node_idx)

def get_madara_full_node_service_config(config_path, network, infura_api_key, sequencer_address, mounted_files):
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
          "https://{}.infura.io/v3/{}".format(network, infura_api_key),
        ],
        files=mounted_files,
    )
