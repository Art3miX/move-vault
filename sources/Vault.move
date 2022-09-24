module Vault::vault {
    use aptos_std::signer::address_of;
    use aptos_std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::type_info::{TypeInfo, type_of};
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

    public entry fun Deposit<CoinType> (sender: signer, amount: u64) acquires Config, State, Vault, User {
        //Make sure deposits are not paused.
        ensure_not_paused();

        //We check to see if vault for this coin exists, if it doesn't we abort here.
        ensure_vault_exists<CoinType>();

        let state = borrow_global_mut<State>(@Vault);

        // We make sure the user exists and set if not.
        ensure_user_exists(&sender, state);

        let user = borrow_global_mut<User>(address_of(&sender));

        //We take the coin from our Vault
        let vault = borrow_global_mut<Vault<CoinType>>(@Vault);
        let coin_id = vault.id;

        //withdraw from the sender
        let sender_coin = coin::withdraw<CoinType>(&sender, amount);

        // Merge the balances
        coin::merge(&mut vault.coin, sender_coin);

        //Check if user already deposited this coin before.
        if(iterable_table::contains(&user.deposits, coin_id)) {
            let deposit = *iterable_table::borrow_mut(&mut user.deposits, coin_id);
            deposit = deposit + coin::value(&sender_coin);
        } else {
            iterable_table::add(&mut user.deposits, coin_id, coin::value(&sender_coin));
        }
    }

    public entry fun Withdraw<CoinType> (sender: &signer, amount: u64) acquires Config, State, Vault, User {
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
        let deposit = *iterable_table::borrow_mut(&mut user.deposits, coin_id);
        deposit = deposit - coin::value(&withdraw);
    }

    /// Pause Vault operation
    public entry fun Pause(admin: &signer) acquires Config {
        verify_admin(admin);

        borrow_global_mut<Config>(address_of(admin)).paused = true;
    }

    /// Unpause Vault operation
    public entry fun Unpause(admin: &signer) acquires Config {
        verify_admin(admin);

        borrow_global_mut<Config>(address_of(admin)).paused = false;
    }

    fun verify_admin(admin: &signer) {
        assert!(address_of(admin) == @Vault, ENOT_ADMIN);
    }

    // Probably a good idea to make a function like that to see if a user can withdraw instead of failing if he can't.
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
}
