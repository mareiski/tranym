import express, {
  type Express,
  type Request,
  type Response,
  type NextFunction,
} from "express";
import { ProofResult, QueryResult, ZKPassport } from "@zkpassport/sdk";
import cors from "cors";
import { Pool, type PoolClient } from "pg";
import jwt from "jsonwebtoken";
import { createHmac, randomUUID } from "node:crypto";
import "dotenv/config";

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------

const app: Express = express();

const PORT = Number(process.env.PORT ?? 3000);
const FRONTEND_URL = process.env.FRONTEND_URL ?? "http://localhost:5173";
const DATABASE_URL = process.env.DATABASE_URL;
const TOKEN_SECRET = process.env.TOKEN_SECRET;
const IDENTIFIER_HASH_SECRET = process.env.IDENTIFIER_HASH_SECRET;

const TOKEN_ISSUER = "passonym-identity";
const TOKEN_AUDIENCE = "passonym-platform";
const TOKEN_LIFETIME_SECONDS = 5 * 60;

if (!DATABASE_URL) {
  throw new Error("DATABASE_URL is not configured");
}

if (!TOKEN_SECRET || TOKEN_SECRET.length < 32) {
  throw new Error("TOKEN_SECRET must contain at least 32 characters");
}

if (!IDENTIFIER_HASH_SECRET || IDENTIFIER_HASH_SECRET.length < 32) {
  throw new Error("IDENTIFIER_HASH_SECRET must contain at least 32 characters");
}

app.use(
  cors({
    origin: FRONTEND_URL,
    credentials: true,
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
  }),
);

app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

const pool = new Pool({
  connectionString: DATABASE_URL,
  max: 10,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
  // Configure DATABASE_URL with SSL when connecting to a remote database.
});

// -----------------------------------------------------------------------------
// ZKPassport
// -----------------------------------------------------------------------------

const zkPassport = new ZKPassport(FRONTEND_URL);

type VerificationRequest = {
  proofs: ProofResult[];
  result: QueryResult;
  signature: string;
};

type VerificationResponse = {
  verified: boolean;
  token?: string;
};

// -----------------------------------------------------------------------------
// Database
// -----------------------------------------------------------------------------

async function initializeDatabase(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS identity_users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      identifier_hash TEXT NOT NULL UNIQUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

/**
 * Derive a keyed identifier before storing it.
 * The original identifier is never persisted in the identity database.
 */
function hashIdentifier(identifier: string): string {
  return createHmac("sha256", IDENTIFIER_HASH_SECRET!)
    .update(identifier, "utf8")
    .digest("hex");
}

async function insertUserIdentifier(
  identifier: string,
  client?: PoolClient,
): Promise<boolean> {
  const identifierHash = hashIdentifier(identifier);
  const db = client ?? pool;

  const result = await db.query(
    `
      INSERT INTO identity_users (identifier_hash)
      VALUES ($1)
      ON CONFLICT (identifier_hash) DO NOTHING
    `,
    [identifierHash],
  );

  return result.rowCount === 1;
}

// -----------------------------------------------------------------------------
// Registration token
// -----------------------------------------------------------------------------

/**
 * The platform server must verify this JWT using TOKEN_SECRET
 * or, preferably, a separately distributed public verification key
 * if asymmetric signing is introduced.
 *
 * The token is short-lived and bound to the registering public key.
 * The platform server must also enforce single-use token consumption.
 */
async function createAndSignToken(signature: string): Promise<string> {
  return jwt.sign(
    {
      publicKey: signature,
      purpose: "register",
    },
    TOKEN_SECRET!,
    {
      algorithm: "HS256",
      issuer: TOKEN_ISSUER,
      audience: TOKEN_AUDIENCE,
      subject: randomUUID(),
      jwtid: randomUUID(),
      expiresIn: TOKEN_LIFETIME_SECONDS,
    },
  );
}

// -----------------------------------------------------------------------------
// Proof verification and registration
// -----------------------------------------------------------------------------

export async function verifyProofs({
  proofs,
  result,
  signature,
}: VerificationRequest): Promise<VerificationResponse> {
  if (
    !Array.isArray(proofs) ||
    proofs.length === 0 ||
    !result ||
    typeof signature !== "string" ||
    signature.length === 0 ||
    signature.length > 4096
  ) {
    throw new Error("Invalid verification request");
  }

  const { query } = zkPassport
    .createQuery()
    .in("nationality", ["Zero Knowledge Republic"])
    .done();

  const { verified, uniqueIdentifier } = await zkPassport.verify({
    proofs,
    originalQuery: query,
    queryResult: result,
    scope: "personhood",
    devMode: process.env.NODE_ENV !== "production",
  });

  if (!verified || !uniqueIdentifier) {
    return { verified: false };
  }

  // Reserve the identifier before issuing the token. The UNIQUE constraint
  // prevents concurrent requests from registering the same identifier twice.
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    const inserted = await insertUserIdentifier(uniqueIdentifier, client);

    if (!inserted) {
      await client.query("ROLLBACK");

      console.warn("User is already registered");

      return { verified: true };
    }

    const token = await createAndSignToken(signature);

    await client.query("COMMIT");

    return {
      verified: true,
      token,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

// -----------------------------------------------------------------------------
// Routes
// -----------------------------------------------------------------------------

app.get("/api", (_req: Request, res: Response) => {
  res.json({
    service: "Passonym Identity Server",
    status: "ok",
  });
});

app.get("/api/health", async (_req: Request, res: Response) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", database: "connected" });
  } catch {
    res.status(503).json({
      status: "error",
      database: "unavailable",
    });
  }
});

app.post(
  "/api/verify",
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Partial<VerificationRequest>;

      if (
        !body ||
        !Array.isArray(body.proofs) ||
        !body.result ||
        typeof body.signature !== "string"
      ) {
        res.status(400).json({
          error: "Invalid request body",
        });
        return;
      }

      const verificationResult = await verifyProofs({
        proofs: body.proofs,
        result: body.result,
        signature: body.signature,
      });

      if (!verificationResult.verified) {
        res.status(401).json({
          verified: false,
          error: "Identity verification failed",
        });
        return;
      }

      res.status(200).json(verificationResult);
    } catch (error) {
      next(error);
    }
  },
);

// -----------------------------------------------------------------------------
// Error handling
// -----------------------------------------------------------------------------

app.use((error: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error("Identity server request failed:", error.message);

  if (res.headersSent) {
    return;
  }

  res.status(500).json({
    error: "Internal server error",
  });
});

// -----------------------------------------------------------------------------
// Startup and shutdown
// -----------------------------------------------------------------------------

async function startServer(): Promise<void> {
  await initializeDatabase();

  const server = app.listen(PORT, () => {
    console.log(`Identity server listening on port ${PORT}`);
  });

  const shutdown = async () => {
    server.close(async () => {
      await pool.end();
      process.exit(0);
    });
  };

  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
}

startServer().catch((error: unknown) => {
  console.error("Failed to start identity server:", error);
  process.exit(1);
});
