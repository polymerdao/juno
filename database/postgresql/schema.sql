-- Create the validator table if it doesn't exist
CREATE TABLE IF NOT EXISTS validator
(
    consensus_address TEXT NOT NULL PRIMARY KEY, /* Validator consensus address */
    consensus_pubkey  TEXT NOT NULL UNIQUE /* Validator consensus public key */
);

-- Create the block table if it doesn't exist
CREATE TABLE IF NOT EXISTS block
(
    height           BIGINT UNIQUE PRIMARY KEY,
    hash             TEXT                        NOT NULL UNIQUE,
    num_txs          INTEGER DEFAULT 0,
    total_gas        BIGINT  DEFAULT 0,
    proposer_address TEXT REFERENCES validator (consensus_address),
    timestamp        TIMESTAMP WITHOUT TIME ZONE NOT NULL
    );
CREATE INDEX IF NOT EXISTS block_height_index ON block (height);
CREATE INDEX IF NOT EXISTS block_hash_index ON block (hash);
CREATE INDEX IF NOT EXISTS block_proposer_address_index ON block (proposer_address);

-- Create the pre_commit table if it doesn't exist
CREATE TABLE IF NOT EXISTS pre_commit
(
    validator_address TEXT                        NOT NULL REFERENCES validator (consensus_address),
    height            BIGINT                      NOT NULL,
    timestamp         TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    voting_power      BIGINT                      NOT NULL,
    proposer_priority BIGINT                      NOT NULL,
    UNIQUE (validator_address, timestamp)
    );
CREATE INDEX IF NOT EXISTS pre_commit_validator_address_index ON pre_commit (validator_address);
CREATE INDEX IF NOT EXISTS pre_commit_height_index ON pre_commit (height);

-- Create the transaction table if it doesn't exist
CREATE TABLE IF NOT EXISTS transaction
(
    hash         TEXT    NOT NULL,
    height       BIGINT  NOT NULL REFERENCES block (height),
    success      BOOLEAN NOT NULL,

    /* Body */
    messages     JSON    NOT NULL DEFAULT '[]'::JSON,
    memo         TEXT,
    signatures   TEXT[]  NOT NULL,

    /* AuthInfo */
    signer_infos JSONB   NOT NULL DEFAULT '[]'::JSONB,
    fee          JSONB   NOT NULL DEFAULT '{}'::JSONB,

    /* Tx response */
    gas_wanted   BIGINT           DEFAULT 0,
    gas_used     BIGINT           DEFAULT 0,
    raw_log      TEXT,
    logs         JSONB,

    /* PSQL partition */
    partition_id BIGINT  NOT NULL DEFAULT 0,

    CONSTRAINT unique_tx UNIQUE (hash, partition_id)
    ) PARTITION BY LIST (partition_id);
CREATE INDEX IF NOT EXISTS transaction_hash_index ON transaction (hash);
CREATE INDEX IF NOT EXISTS transaction_height_index ON transaction (height);
CREATE INDEX IF NOT EXISTS transaction_partition_id_index ON transaction (partition_id);
CREATE INDEX IF NOT EXISTS transaction_logs_index ON transaction USING GIN(logs);

-- Create the message table if it doesn't exist
CREATE TABLE IF NOT EXISTS message
(
    transaction_hash            TEXT   NOT NULL,
    index                       BIGINT NOT NULL,
    type                        TEXT   NOT NULL,
    value                       JSON   NOT NULL,
    involved_accounts_addresses TEXT[] NOT NULL,

    /* PSQL partition */
    partition_id                BIGINT NOT NULL DEFAULT 0,
    height                      BIGINT NOT NULL,
    FOREIGN KEY (transaction_hash, partition_id) REFERENCES transaction (hash, partition_id),
    CONSTRAINT unique_message_per_tx UNIQUE (transaction_hash, index, partition_id)
    ) PARTITION BY LIST (partition_id);
CREATE INDEX IF NOT EXISTS message_transaction_hash_index ON message (transaction_hash);
CREATE INDEX IF NOT EXISTS message_type_index ON message (type);
CREATE INDEX IF NOT EXISTS message_involved_accounts_index ON message USING GIN(involved_accounts_addresses);

-- Create the messages_by_address function if it doesn't exist
CREATE OR REPLACE FUNCTION messages_by_address(
    addresses TEXT[],
    types TEXT[],
    "limit" BIGINT = 100,
    "offset" BIGINT = 0)
    RETURNS SETOF message AS
$$
SELECT * FROM message
WHERE (cardinality(types) = 0 OR type = ANY (types))
  AND addresses && involved_accounts_addresses
ORDER BY height DESC LIMIT "limit" OFFSET "offset"
    $$ LANGUAGE sql STABLE;

-- Create the pruning table if it doesn't exist
CREATE TABLE IF NOT EXISTS pruning
(
    last_pruned_height BIGINT NOT NULL
);