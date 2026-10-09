-- Seed key for a random roll that should differ between the two players.
--
-- Both games run from the same seed, and pseudorandom(key) gives the same
-- sequence for the same key on both games. So when each player's game rolls an
-- Attack with a shared key (for example "mp_blind_inflation"), the Nth roll on
-- one game equals the Nth roll on the other: the attacks mirror each other.
-- Adding the player's lobby role gives each game its own sequence.
--
-- Use this only for rolls that must differ. Anything both games must agree on
-- (for example the Duel bounty goal) keeps a shared key.
function MP.UTILS.player_seed_key(key)
	return key .. (MP.LOBBY.is_host and "_host" or "_guest")
end
