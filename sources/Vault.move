module Vault::vault {
    use aptos_std::signer::address_of;
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use Vault::iterable_table;

    struct Config has key {
        paused: bool,
        coin_index: u64,
    }

    struct State has key {
        users: vector<address>
        //Can add a table of total amounts of all coins.
    }

    struct Vault<phantom CoinType> has key {
        id: u64,
        coin: Coin<CoinType>
    }

    struct User has key {
        deposits: iterable_table::IterableTable<u64, u64>
    }

    const ENOT_ADMIN: u64 = 0;
    const ECOIN_NOT_EXISTS: u64 = 1;
    const EDEPOSIT_WITHDRAWL_PAUSED: u64 = 2;

    public entry fun init_vault(admin: &signer) {
        verify_admin(admin);

        move_to<Config>(admin, Config {
            paused: false,
            coin_index: 0,
        });

        move_to<State>(admin, State {
            users: vector::empty(),
        })
    }

    public entry fun admin_add_coin<CoinType>(admin: &signer) acquires Config {
        verify_admin(admin);

        //Get the config so we can get the index of the last coin, and add to the index
        let config = borrow_global_mut<Config>(@Vault);
        config.coin_index = config.coin_index + 1;

        move_to(admin, Vault<CoinType> {
            id: config.coin_index,
            coin: coin::zero<CoinType>(),
        })
    }

    public entry fun deposit<CoinType> (sender: &signer, amount: u64) acquires Config, State, Vault, User {
        //Make sure deposits are not paused.
        ensure_not_paused();

        //We check to see if vault for this coin exists, if it doesn't we abort here.
        ensure_vault_exists<CoinType>();

        let state = borrow_global_mut<State>(@Vault);

        // We make sure the user exists and set if not.
        ensure_user_exists(sender, state);

        let user = borrow_global_mut<User>(address_of(sender));

        //We take the coin from our Vault
        let vault = borrow_global_mut<Vault<CoinType>>(@Vault);
        let coin_id = vault.id;

        //withdraw from the sender
        let sender_coin = coin::withdraw<CoinType>(sender, amount);

        // Merge the balances
        coin::merge(&mut vault.coin, sender_coin);

        //Check if user already deposited this coin before.
        if(iterable_table::contains(&user.deposits, coin_id)) {
            let deposit = iterable_table::remove(&mut user.deposits, coin_id);
            iterable_table::add(&mut user.deposits, coin_id, (deposit + amount));
        } else {
            iterable_table::add(&mut user.deposits, coin_id, amount);
        }
    }

    public entry fun withdraw<CoinType> (sender: &signer, amount: u64) acquires Config, State, Vault, User {
        //Make sure deposits are not paused.
        ensure_not_paused();

        //We check to see if vault for this coin exists, if it doesn't we abort here.
        ensure_vault_exists<CoinType>();

        let state = borrow_global_mut<State>(@Vault);

        // We make sure the user exists and set if not.
        ensure_user_exists(sender, state);

        let user = borrow_global_mut<User>(address_of(sender));

        //We take the coin from our Vault
        let vault = borrow_global_mut<Vault<CoinType>>(@Vault);
        let coin_id = vault.id;

        //withdraw from the vault
        let withdraw = coin::extract<CoinType>(&mut vault.coin, amount);

        if (!coin::is_account_registered<CoinType>(address_of(sender))) {
            coin::register<CoinType>(sender);
        };

        // deposit into the user
        coin::deposit(address_of(sender), withdraw);

        // Update the deposit of the sender
        let deposit = iterable_table::remove(&mut user.deposits, coin_id);
        iterable_table::add(&mut user.deposits, coin_id, (deposit - amount));
    }

    /// Pause Vault operation
    public entry fun pause(admin: &signer) acquires Config {
        verify_admin(admin);

        borrow_global_mut<Config>(address_of(admin)).paused = true;
    }

    /// Unpause Vault operation
    public entry fun unpause(admin: &signer) acquires Config {
        verify_admin(admin);

        borrow_global_mut<Config>(address_of(admin)).paused = false;
    }

    fun verify_admin(admin: &signer) {
        assert!(address_of(admin) == @Vault, ENOT_ADMIN);
    }

    // Probably a good idea to make a function/query like that to see if a user can withdraw instead of failing if he can't.
    // public fun can_withdraw(sender: signer) {
    //
    // }

    public fun ensure_not_paused() acquires Config {
        let config = borrow_global<Config>(@Vault);

        assert!(config.paused == false, EDEPOSIT_WITHDRAWL_PAUSED)
    }

    public fun ensure_vault_exists<CoinType>() {
        assert!(exists<Vault<CoinType>>(@Vault), ECOIN_NOT_EXISTS);
    }

    public fun ensure_user_exists(user: &signer, state: &mut State) {
        if (!exists<User>(address_of(user))) {
            vector::push_back(&mut state.users, address_of(user));

            move_to(user, User {
                deposits: iterable_table::new<u64, u64>(),
            })
        }
    }

    // TESTS
    struct TestCoin {}

    struct SomeCoin has key {
        test_coin: Coin<TestCoin>,

        cap: coin::MintCapability<TestCoin>,
        burn: coin::BurnCapability<TestCoin>,
        freeze: coin::FreezeCapability<TestCoin>,
    }

    fun init_coin_store(user: &signer) acquires SomeCoin {
        coin::register<TestCoin>(user);
        let faucet_amount = 1000;
        let some_coins = borrow_global_mut<SomeCoin>(@Vault);
        let test_coin = coin::extract(&mut some_coins.test_coin, faucet_amount);

        coin::deposit(address_of(user), test_coin);
    }

    fun do_init(admin: &signer)  acquires Config{
        use std::string;
        let name = string::utf8(b"name");

        let (burn, freeze, cap) = coin::initialize<TestCoin>(admin, copy name, copy name, 0, false);
        let mint_amount = 1000000000000;

        move_to(admin, SomeCoin {
            test_coin: coin::mint(mint_amount, &cap),
            burn,
            cap,
            freeze,
        });

        init_vault(admin);
        admin_add_coin<TestCoin>(admin);
    }

    #[test_only(admin=@Vault, user=@0x1001)]
    fun test_init(admin: &signer, user: &signer) acquires Config, SomeCoin {
        use aptos_framework::account;
        account::create_account_for_test(address_of(admin));
        account::create_account_for_test(address_of(user));

        do_init(admin);
        init_coin_store(user);
    }

    #[test(admin=@Vault, user=@0x1001)]
    fun test_deposit_success(admin: &signer, user: &signer) acquires Config, SomeCoin, State, Vault, User {
        test_init(admin, user);

        deposit<TestCoin>(user, 999);
    }

    #[test(admin=@Vault, user=@0x1001)]
    #[expected_failure]
    fun test_deposit_fail(admin: &signer, user: &signer) acquires Config, SomeCoin, State, Vault, User {
        test_init(admin, user);

        deposit<TestCoin>(user, 10000);
    }

    #[test(admin=@Vault, user=@0x1001)]
    fun test_withdraw_success(admin: &signer, user: &signer) acquires Config, SomeCoin, State, Vault, User {
        test_init(admin, user);

        deposit<TestCoin>(user, 1000);
        withdraw<TestCoin>(user, 1000);
    }

    #[test(admin=@Vault, user=@0x1001)]
    #[expected_failure]
    fun test_withdraw_fail(admin: &signer, user: &signer) acquires Config, SomeCoin, State, Vault, User {
        test_init(admin, user);

        deposit<TestCoin>(user, 1000);
        withdraw<TestCoin>(user, 2000);
    }

    #[test(admin=@Vault, user=@0x1001)]
    #[expected_failure]
    fun test_pause(admin: &signer, user: &signer) acquires Config, SomeCoin, State, Vault, User {
        test_init(admin, user);

        pause(admin);

        deposit<TestCoin>(user, 1000);
    }

    #[test(admin=@Vault, user=@0x1001)]
    fun test_unpause(admin: &signer, user: &signer) acquires Config, SomeCoin, State, Vault, User {
        test_init(admin, user);

        pause(admin);

        unpause(admin);

        deposit<TestCoin>(user, 1000);
    }
}
