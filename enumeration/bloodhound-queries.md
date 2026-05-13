# BloodHound Custom Queries

## Setup

```
Neo4j: http://localhost:7474  (neo4j / neo4j)
BloodHound: http://localhost:7474 -> connect
```

Import SharpHound ZIP in BloodHound GUI.

---

## Attack Path Queries

```cypher
-- Shortest path from attacker.01 to Domain Admins
MATCH (u:User {name:"ATTACKER.01@CORP.LOCAL"}),(g:Group {name:"DOMAIN ADMINS@CORP.LOCAL"}),
      p=shortestPath((u)-[*1..]->(g))
RETURN p

-- All paths to Enterprise Admins
MATCH (n),(m:Group {name:"ENTERPRISE ADMINS@CORP.LOCAL"}),
      p=shortestPath((n)-[*1..]->(m))
WHERE NOT n=m RETURN p LIMIT 25

-- Find all DA paths from non-DA users
MATCH (u:User),(g:Group {name:"DOMAIN ADMINS@CORP.LOCAL"}),
      p=shortestPath((u)-[*1..]->(g))
WHERE NOT (u)-[:MemberOf]->(g)
RETURN p LIMIT 10
```

---

## Kerberoast / AS-REP

```cypher
-- All Kerberoastable users
MATCH (u:User {hasspn:true})
WHERE NOT u.name STARTS WITH "krbtgt"
RETURN u.name, u.serviceprincipalnames

-- AS-REP Roastable users
MATCH (u:User {dontreqpreauth:true})
RETURN u.name

-- Kerberoastable users who are admins
MATCH (u:User {hasspn:true})-[:AdminTo]->(c:Computer)
RETURN u.name, c.name
```

---

## Delegation

```cypher
-- Unconstrained delegation computers
MATCH (c:Computer {unconstraineddelegation:true})
WHERE NOT c.name STARTS WITH "DC"
RETURN c.name

-- Constrained delegation users
MATCH (u:User) WHERE u.allowedtodelegate IS NOT NULL RETURN u.name, u.allowedtodelegate

-- RBCD configurations
MATCH (c:Computer) WHERE c.allowedtoactonbehalfofotheridentity IS NOT NULL
RETURN c.name
```

---

## ACLs

```cypher
-- Users with DCSync rights
MATCH p=(n)-[:GetChanges|GetChangesAll*1..]->(d:Domain)
RETURN p

-- All GenericAll edges
MATCH p=(u)-[:GenericAll]->(t)
WHERE u:User OR u:Group
RETURN p LIMIT 50

-- All WriteDACL edges
MATCH p=(u)-[:WriteDacl]->(t)
RETURN p LIMIT 50

-- All ForceChangePassword edges
MATCH p=(u)-[:ForceChangePassword]->(t)
RETURN p

-- Find objects where non-admin users have dangerous rights
MATCH p=(u:User)-[:GenericAll|GenericWrite|WriteDacl|WriteOwner|ForceChangePassword|Owns]->(t)
WHERE NOT (u)-[:MemberOf]->(:Group {name:"DOMAIN ADMINS@CORP.LOCAL"})
RETURN p LIMIT 100
```

---

## High-Value Targets

```cypher
-- Find all DA group members
MATCH (u:User)-[:MemberOf*1..]->(g:Group {name:"DOMAIN ADMINS@CORP.LOCAL"})
RETURN u.name

-- Find computers where DA accounts have sessions
MATCH (u:User)-[:HasSession]->(c:Computer)
WHERE u.name IN ["ADMINISTRATOR@CORP.LOCAL","ADMIN1@CORP.LOCAL"]
RETURN u.name, c.name

-- Find non-DA accounts with local admin rights
MATCH p=(u:User)-[:AdminTo]->(c:Computer)
WHERE NOT (u)-[:MemberOf]->(:Group {name:"DOMAIN ADMINS@CORP.LOCAL"})
RETURN u.name, c.name
```

---

## Cross-Domain Queries

```cypher
-- Find all trusts
MATCH (d1:Domain)-[t:TrustedBy]->(d2:Domain)
RETURN d1.name, d2.name, t.transitive, t.isacl

-- Shortest cross-domain path
MATCH (u:User {domain:"DEV.CORP.LOCAL"}),(ea:Group {name:"ENTERPRISE ADMINS@CORP.LOCAL"}),
      p=shortestPath((u)-[*1..]->(ea))
RETURN p LIMIT 5
```

---

## Cleanup / Stats

```cypher
-- Count all users
MATCH (u:User) RETURN count(u)

-- Count enabled users
MATCH (u:User {enabled:true}) RETURN count(u)

-- List all computers
MATCH (c:Computer) RETURN c.name, c.operatingsystem ORDER BY c.name
```
