require("dotenv").config();

const express = require("express");
const cors = require("cors");
const path = require("path");
const fs = require("fs");
const multer = require("multer");
const crypto = require("crypto");
const nodemailer = require("nodemailer");

const {
  initializeApp,
  cert,
  getApps,
} = require("firebase-admin/app");

const {
  getAuth,
} = require("firebase-admin/auth");

const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");

// ============================================================
// APP
// ============================================================

const app = express();

app.use((req, res, next) => {
  console.log(
    `[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`
  );
  next();
});

app.use(
  cors({
    origin: true,
    methods: [
      "GET",
      "POST",
      "PUT",
      "PATCH",
      "DELETE",
      "OPTIONS",
    ],
    allowedHeaders: [
      "Content-Type",
      "Authorization",
    ],
    optionsSuccessStatus: 204,
  })
);

app.options("*", cors());

app.use(express.json());
app.use(
  express.urlencoded({
    extended: true,
  })
);
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ============================================================
// FIREBASE ADMIN - LOCAL + VERCEL
// ============================================================

let serviceAccount;

// Vercel / Production
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  try {
    serviceAccount = JSON.parse(
      process.env.FIREBASE_SERVICE_ACCOUNT
    );
  } catch (error) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT contains invalid JSON."
    );
  }
}

// Local development
else {
  const serviceAccountPath = path.join(
    __dirname,
    "serviceAccountKey.json"
  );

  if (!fs.existsSync(serviceAccountPath)) {
    throw new Error(
      "serviceAccountKey.json file is missing."
    );
  }

  try {
    serviceAccount = require(
      serviceAccountPath
    );
  } catch (error) {
    throw new Error(
      "Could not load serviceAccountKey.json."
    );
  }
}

// Validate Firebase service account
if (
  !serviceAccount ||
  typeof serviceAccount.project_id !== "string"
) {
  throw new Error(
    "Invalid Firebase service account configuration."
  );
}

// Initialize Firebase Admin
if (getApps().length === 0) {
  initializeApp({
    credential: cert(serviceAccount),
  });
}

const auth = getAuth();
const db = getFirestore();

console.log(
  "Firebase Admin connected successfully"
);

// ============================================================
// SERVER
// ============================================================

const PORT =
  Number(process.env.PORT) || 3000;

const PUBLIC_BASE_URL =
  process.env.PUBLIC_BASE_URL ||
  `http://localhost:${PORT}`;

// ============================================================
// SMTP
// ============================================================

let transporter = null;

if (
  process.env.SMTP_HOST &&
  process.env.SMTP_USER &&
  process.env.SMTP_PASS
) {
  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,

    port: Number(
      process.env.SMTP_PORT || 587
    ),

    secure:
      String(
        process.env.SMTP_SECURE
      ).toLowerCase() === "true",

    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
}


// ============================================================
// PROFILE UPLOAD
// ============================================================

// Vercel does not allow writing to /var/task.
// Use temporary storage on Vercel.
// Local development will continue to use uploads/profile.
const profileUploadDir = process.env.VERCEL
  ? "/tmp/billx-profile"
  : path.join(
      __dirname,
      "uploads",
      "profile"
    );

// Create upload directory if it does not exist
if (!fs.existsSync(profileUploadDir)) {
  fs.mkdirSync(profileUploadDir, {
    recursive: true,
  });
}

console.log(
  "Profile upload folder:",
  profileUploadDir
);

// ============================================================
// MULTER STORAGE
// ============================================================

const profileStorage =
  multer.diskStorage({
    destination: function (
      req,
      file,
      cb
    ) {
      cb(
        null,
        profileUploadDir
      );
    },

    filename: function (
      req,
      file,
      cb
    ) {
      const extension =
        path
          .extname(
            file.originalname
          )
          .toLowerCase() || ".jpg";

      const randomName =
        crypto
          .randomBytes(18)
          .toString("hex");

      cb(
        null,
        `${randomName}${extension}`
      );
    },
  });

// ============================================================
// MULTER UPLOAD
// ============================================================

const profileUpload =
  multer({
    storage: profileStorage,

    limits: {
      fileSize:
        5 * 1024 * 1024,
    },

    fileFilter:
      function (
        req,
        file,
        cb
      ) {
        const extension =
          path
            .extname(
              file.originalname
            )
            .toLowerCase();

        const allowed = [
          ".jpg",
          ".jpeg",
          ".png",
          ".webp",
        ];

        if (
          allowed.includes(
            extension
          )
        ) {
          cb(null, true);
          return;
        }

        cb(
          new Error(
            "Only JPG, JPEG, PNG and WEBP images are allowed."
          )
        );
      },
  });

// ============================================================
// SERVE PROFILE IMAGES
// ============================================================

app.use(
  "/uploads/profile",
  express.static(
    profileUploadDir
  )
);

// ============================================================
// BASIC ROUTES
// ============================================================

app.get("/", (req, res) => {
  res.json({
    success: true,
    message:
      "BillX Backend + Firebase Admin is running",
  });
});

app.get("/test", (req, res) => {
  res.json({
    success: true,
    message:
      "BillX Backend Connected Successfully",
  });
});

app.get(
  "/test-firebase",
  async (req, res) => {
    try {
      await auth.listUsers(1);

      res.json({
        success: true,
        message:
          "Firebase Admin connection successful",
      });
    } catch (error) {
      console.error(
        "Firebase test error:",
        error
      );

      res.status(500).json({
        success: false,
        message:
          "Firebase Admin connection failed",
        error:
          error.message,
      });
    }
  }
);

// ============================================================
// AUTH MIDDLEWARE
// ============================================================

async function requireAuth(
  req,
  res,
  next
) {
  try {
    const authorization =
      req.headers.authorization ||
      "";

    console.log(
      "Authorization header exists:",
      authorization.length > 0
    );

    if (
      !authorization.startsWith(
        "Bearer "
      )
    ) {
      console.log(
        "AUTH ERROR: Missing Bearer token"
      );

      return res.status(401).json({
        success: false,
        message:
          "Authorization token is required.",
      });
    }

    const token =
      authorization
        .substring(7)
        .trim();

    if (!token) {
      return res.status(401).json({
        success: false,
        message:
          "Invalid authorization token.",
      });
    }

    const decodedToken =
      await auth.verifyIdToken(
        token
      );

    req.user =
      decodedToken;

    console.log(
      "AUTH SUCCESS"
    );

    console.log(
      "UID:",
      decodedToken.uid
    );

    console.log(
      "Email:",
      decodedToken.email
    );

    next();
  } catch (error) {
    console.error(
      "Authentication error:",
      error
    );

    return res.status(401).json({
      success: false,
      message:
        "Unauthorized.",
      error:
        error.message,
    });
  }
}

// ============================================================
// ADMIN MIDDLEWARE
// ============================================================

async function requireAdmin(
  req,
  res,
  next
) {
  try {
    console.log(
      "========== ADMIN CHECK =========="
    );

    if (!req.user) {
      return res.status(401).json({
        success: false,
        message:
          "Unauthorized.",
      });
    }

    const uid =
      req.user.uid;

    const email =
      String(
        req.user.email || ""
      )
        .trim()
        .toLowerCase();

    const adminEmails =
      String(
        process.env.ADMIN_EMAILS ||
        ""
      )
        .split(",")
        .map(
          (value) =>
            value
              .trim()
              .toLowerCase()
        )
        .filter(Boolean);

    const adminUids =
      String(
        process.env.ADMIN_UIDS ||
        ""
      )
        .split(",")
        .map(
          (value) =>
            value.trim()
        )
        .filter(Boolean);

    console.log(
      "Firebase UID:",
      uid
    );

    console.log(
      "Firebase Email:",
      email
    );

    console.log(
      "ADMIN_EMAILS:",
      adminEmails
    );

    console.log(
      "ADMIN_UIDS:",
      adminUids
    );

    const emailMatch =
      adminEmails.includes(
        email
      );

    const uidMatch =
      adminUids.includes(
        uid
      );

    if (emailMatch) {
      console.log(
        "ADMIN RESULT: Email matched"
      );

      return next();
    }

    if (uidMatch) {
      console.log(
        "ADMIN RESULT: UID matched"
      );

      return next();
    }

    try {
      const userDoc =
        await db
          .collection("users")
          .doc(uid)
          .get();

      if (userDoc.exists) {
        const userData =
          userDoc.data() ||
          {};

        const role =
          String(
            userData.role ||
            ""
          )
            .trim()
            .toLowerCase();

        console.log(
          "Firestore role:",
          role
        );

        if (
          role === "admin"
        ) {
          console.log(
            "ADMIN RESULT: Firestore role matched"
          );

          return next();
        }
      }
    } catch (
      firestoreError
    ) {
      console.error(
        "Firestore admin-role check error:",
        firestoreError
      );
    }

    console.log(
      "ADMIN RESULT: ACCESS DENIED"
    );

    return res.status(403).json({
      success: false,
      message:
        "Admin access required.",
    });
  } catch (error) {
    console.error(
      "requireAdmin ERROR:",
      error
    );

    return res.status(500).json({
      success: false,
      message:
        "Could not verify admin account.",
    });
  }
}

// ============================================================
// LICENSE HELPERS
// ============================================================

function randomLicensePart(
  length = 4
) {
  const characters =
    "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  let result = "";

  for (
    let i = 0;
    i < length;
    i++
  ) {
    const index =
      crypto.randomInt(
        0,
        characters.length
      );

    result +=
      characters[index];
  }

  return result;
}

function generateLicenseKey() {
  return [
    "BILLX",
    randomLicensePart(4),
    randomLicensePart(4),
    randomLicensePart(4),
  ].join("-");
}

function normalizeLicenseKey(
  key
) {
  return String(
    key || ""
  )
    .trim()
    .toUpperCase()
    .replace(
      /\s+/g,
      ""
    );
}

function normalizeEmail(
  email
) {
  return String(
    email || ""
  )
    .trim()
    .toLowerCase();
}

// ============================================================
// CREATE LICENSE
// ============================================================

app.post(
  "/admin/license/create",
  requireAuth,
  requireAdmin,
  async (req, res) => {
    try {
      const customerEmail =
        normalizeEmail(
          req.body.email
        );

      let days =
        Number(
          req.body.days
        );

      if (
        !Number.isFinite(days) ||
        days <= 0
      ) {
        days = 365;
      }

      if (days > 3650) {
        days = 3650;
      }

      if (!customerEmail) {
        return res.status(400).json({
          success: false,
          message:
            "Customer Gmail is required.",
        });
      }

      let licenseKey = "";

      for (
        let attempt = 0;
        attempt < 20;
        attempt++
      ) {
        const possibleKey =
          generateLicenseKey();

        const existing =
          await db
            .collection(
              "licenses"
            )
            .doc(
              possibleKey
            )
            .get();

        if (
          !existing.exists
        ) {
          licenseKey =
            possibleKey;

          break;
        }
      }

      if (!licenseKey) {
        return res.status(500).json({
          success: false,
          message:
            "Could not generate a unique license key.",
        });
      }

      let assignedUserId =
        null;

      try {
        const customerUser =
          await auth.getUserByEmail(
            customerEmail
          );

        assignedUserId =
          customerUser.uid;
      } catch (error) {
        assignedUserId =
          null;
      }

      const expiresAt =
        Timestamp.fromDate(
          new Date(
            Date.now() +
              days *
                24 *
                60 *
                60 *
                1000
          )
        );

      await db
        .collection(
          "licenses"
        )
        .doc(
          licenseKey
        )
        .set({
          licenseKey:
            licenseKey,

          status:
            "active",

          assignedEmail:
            customerEmail,

          assignedUserId:
            assignedUserId,

          createdBy:
            req.user.uid,

          createdByEmail:
            req.user.email ||
            null,

          createdAt:
            FieldValue.serverTimestamp(),

          activatedAt:
            null,

          activatedUserId:
            null,

          lastVerifiedAt:
            null,

          expiresAt:
            expiresAt,
        });

      return res.status(201).json({
        success: true,

        message:
          "License created successfully.",

        licenseKey:
          licenseKey,

        assignedEmail:
          customerEmail,

        expiresAt:
          expiresAt
            .toDate()
            .toISOString(),
      });
    } catch (error) {
      console.error(
        "CREATE LICENSE ERROR:",
        error
      );

      return res.status(500).json({
        success: false,

        message:
          error.message ||
          "Could not create license.",
      });
    }
  }
);

// ============================================================
// VERIFY / ACTIVATE LICENSE
// ============================================================

app.post(
  "/license/verify",
  requireAuth,
  async (req, res) => {
    try {
      const cleanKey =
        normalizeLicenseKey(
          req.body.licenseKey
        );

      if (!cleanKey) {
        return res.status(400).json({
          success: false,
          message:
            "Please enter a license key.",
        });
      }

      const licenseRef =
        db
          .collection(
            "licenses"
          )
          .doc(
            cleanKey
          );

      await db.runTransaction(
        async (
          transaction
        ) => {
          const snapshot =
            await transaction.get(
              licenseRef
            );

          if (
            !snapshot.exists
          ) {
            const error =
              new Error(
                "License key not found."
              );

            error.code =
              "LICENSE_NOT_FOUND";

            throw error;
          }

          const license =
            snapshot.data() ||
            {};

          const status =
            String(
              license.status ||
                "active"
            )
              .trim()
              .toLowerCase();

          if (
            status ===
              "revoked" ||
            status ===
              "disabled"
          ) {
            const error =
              new Error(
                "This license has been revoked."
              );

            error.code =
              "LICENSE_REVOKED";

            throw error;
          }

          const expiresAt =
            license.expiresAt;

          if (
            expiresAt &&
            typeof expiresAt.toDate ===
              "function"
          ) {
            if (
              expiresAt
                .toDate()
                .getTime() <
              Date.now()
            ) {
              const error =
                new Error(
                  "This license has expired."
                );

              error.code =
                "LICENSE_EXPIRED";

              throw error;
            }
          }

          const currentUserId =
            req.user.uid;

          const currentEmail =
            normalizeEmail(
              req.user.email
            );

          const assignedEmail =
            normalizeEmail(
              license.assignedEmail
            );

          const assignedUserId =
            license.assignedUserId ||
            null;

          if (
            assignedEmail &&
            currentEmail &&
            assignedEmail !==
              currentEmail
          ) {
            const error =
              new Error(
                "This license is assigned to another Gmail account."
              );

            error.code =
              "EMAIL_MISMATCH";

            throw error;
          }

          if (
            assignedUserId &&
            assignedUserId !==
              currentUserId
          ) {
            const error =
              new Error(
                "This license is already assigned to another account."
              );

            error.code =
              "USER_MISMATCH";

            throw error;
          }

          const updateData = {
            status:
              "active",

            lastVerifiedAt:
              FieldValue.serverTimestamp(),

            activatedUserId:
              currentUserId,
          };

          if (
            !assignedUserId
          ) {
            updateData.assignedUserId =
              currentUserId;
          }

          if (
            !license.activatedAt
          ) {
            updateData.activatedAt =
              FieldValue.serverTimestamp();
          }

          transaction.update(
            licenseRef,
            updateData
          );
        }
      );

      return res.json({
        success: true,

        message:
          "License activated successfully.",

        licenseKey:
          cleanKey,
      });
    } catch (error) {
      console.error(
        "License verification error:",
        error
      );

      let statusCode =
        400;

      let message =
        error.message ||
        "License verification failed.";

      switch (
        error.code
      ) {
        case "LICENSE_NOT_FOUND":
          statusCode = 404;
          message =
            "License key not found.";
          break;

        case "LICENSE_REVOKED":
          statusCode = 403;
          message =
            "This license has been revoked.";
          break;

        case "LICENSE_EXPIRED":
          statusCode = 403;
          message =
            "This license has expired.";
          break;

        case "EMAIL_MISMATCH":
          statusCode = 403;
          message =
            "This license is assigned to another Gmail account.";
          break;

        case "USER_MISMATCH":
          statusCode = 403;
          message =
            "This license is already assigned to another account.";
          break;
      }

      return res.status(
        statusCode
      ).json({
        success: false,
        message:
          message,
      });
    }
  }
);

// ============================================================
// ADMIN - LIST LICENSES
// ============================================================

app.get(
  "/admin/licenses",
  requireAuth,
  requireAdmin,
  async (req, res) => {
    try {
      const snapshot =
        await db
          .collection(
            "licenses"
          )
          .orderBy(
            "createdAt",
            "desc"
          )
          .limit(200)
          .get();

      const licenses =
        snapshot.docs.map(
          (doc) => {
            const data =
              doc.data();

            return {
              id:
                doc.id,

              licenseKey:
                data.licenseKey ||
                doc.id,

              status:
                data.status ||
                "active",

              assignedEmail:
                data.assignedEmail ||
                null,

              assignedUserId:
                data.assignedUserId ||
                null,

              activatedUserId:
                data.activatedUserId ||
                null,

              createdBy:
                data.createdBy ||
                null,

              createdByEmail:
                data.createdByEmail ||
                null,

              createdAt:
                data.createdAt
                  ?.toDate()
                  ?.toISOString() ||
                null,

              activatedAt:
                data.activatedAt
                  ?.toDate()
                  ?.toISOString() ||
                null,

              expiresAt:
                data.expiresAt
                  ?.toDate()
                  ?.toISOString() ||
                null,
            };
          }
        );

      return res.json({
        success: true,
        licenses:
          licenses,
      });
    } catch (error) {
      console.error(
        "License list error:",
        error
      );

      return res.status(500).json({
        success: false,
        message:
          "Could not load licenses.",
      });
    }
  }
);

// ============================================================
// ADMIN - REVOKE LICENSE
// ============================================================

app.post(
  "/admin/license/revoke",
  requireAuth,
  requireAdmin,
  async (req, res) => {
    try {
      const cleanKey =
        normalizeLicenseKey(
          req.body.licenseKey
        );

      if (!cleanKey) {
        return res.status(400).json({
          success: false,
          message:
            "License key is required.",
        });
      }

      const licenseRef =
        db
          .collection(
            "licenses"
          )
          .doc(
            cleanKey
          );

      const snapshot =
        await licenseRef.get();

      if (
        !snapshot.exists
      ) {
        return res.status(404).json({
          success: false,
          message:
            "License not found.",
        });
      }

      await licenseRef.update({
        status:
          "revoked",

        revokedAt:
          FieldValue.serverTimestamp(),

        revokedBy:
          req.user.uid,
      });

      return res.json({
        success: true,
        message:
          "License revoked successfully.",
      });
    } catch (error) {
      console.error(
        "Revoke license error:",
        error
      );

      return res.status(500).json({
        success: false,
        message:
          "Could not revoke license.",
      });
    }
  }
);

// ============================================================
// PROFILE PHOTO
// ============================================================

app.post(
  "/profile/photo",
  requireAuth,
  profileUpload.single(
    "file"
  ),
  async (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({
          success: false,
          message:
            "No profile image was uploaded.",
        });
      }

      const photoUrl =
        `${PUBLIC_BASE_URL}/uploads/profile/${req.file.filename}`;

      console.log(
        "Profile photo uploaded:",
        req.file.filename
      );

      return res.json({
        success: true,
        message:
          "Profile picture uploaded successfully",
        photoUrl:
          photoUrl,
      });
    } catch (error) {
      console.error(
        "Profile upload error:",
        error
      );

      return res.status(500).json({
        success: false,
        message:
          "Profile photo upload failed.",
      });
    }
  }
);

// ============================================================
// SMTP TEST
// ============================================================

app.get(
  "/test-smtp",
  async (req, res) => {
    try {
      if (!transporter) {
        return res.status(500).json({
          success: false,
          message:
            "SMTP configuration is missing.",
        });
      }

      await transporter.verify();

      return res.json({
        success: true,
        message:
          "SMTP connection successful",
      });
    } catch (error) {
      console.error(
        "SMTP test error:",
        error
      );

      return res.status(500).json({
        success: false,
        message:
          "SMTP connection failed",
        error:
          error.message,
      });
    }
  }
);

// ============================================================
// TEST EMAIL
// ============================================================

app.get(
  "/test-email",
  async (req, res) => {
    try {
      if (!transporter) {
        return res.status(500).json({
          success: false,
          message:
            "SMTP configuration is missing.",
        });
      }

      const to =
        req.query.to ||
        process.env.SMTP_USER;

      await transporter.sendMail({
        from:
          process.env.SMTP_FROM ||
          process.env.SMTP_USER,

        to: to,

        subject:
          "BillX Test Email",

        text:
          "BillX backend email test successful.",
      });

      return res.json({
        success: true,
        message:
          "Test email sent successfully",
      });
    } catch (error) {
      console.error(
        "Test email error:",
        error
      );

      return res.status(500).json({
        success: false,
        message:
          "Test email failed",
        error:
          error.message,
      });
    }
  }
);

// ============================================================
// SEND VERIFICATION
// ============================================================

app.post(
  "/send-verification",
  requireAuth,
  async (req, res) => {
    try {
      if (!transporter) {
        return res.status(500).json({
          success: false,
          message:
            "SMTP configuration is missing.",
        });
      }

      const email =
        normalizeEmail(
          req.body.email ||
            req.user.email
        );

      if (!email) {
        return res.status(400).json({
          success: false,
          message:
            "Email is required.",
        });
      }

      const verificationLink =
        await auth.generateEmailVerificationLink(
          email,
          {
            url:
              process.env
                .VERIFICATION_REDIRECT_URL ||
              "https://billx-478f4.web.app",

            handleCodeInApp:
              false,
          }
        );

      await transporter.sendMail({
        from:
          process.env.SMTP_FROM ||
          process.env.SMTP_USER,

        to: email,

        subject:
          "Verify your BillX account",

        html: `
          <div style="font-family:Arial,sans-serif">
            <h2>BillX Email Verification</h2>

            <p>
              Please click the button below
              to verify your BillX account.
            </p>

            <p>
              <a
                href="${verificationLink}"
                style="
                  display:inline-block;
                  padding:12px 20px;
                  background:#1565C0;
                  color:white;
                  text-decoration:none;
                  border-radius:6px;
                "
              >
                Verify Email
              </a>
            </p>

            <p>
              If you did not create this
              account, you can ignore this email.
            </p>
          </div>
        `,
      });

      return res.json({
        success: true,
        message:
          "Verification email sent successfully.",
      });
    } catch (error) {
      console.error(
        "Verification email error:",
        error
      );

      return res.status(500).json({
        success: false,
        message:
          "Could not send verification email.",
        error:
          error.message,
      });
    }
  }
);

// ============================================================
// ERROR HANDLER
// ============================================================

app.use(
  (
    err,
    req,
    res,
    next
  ) => {
    console.error(
      "SERVER ERROR:",
      err
    );

    return res.status(500).json({
      success: false,
      message:
        err.message ||
        "Internal server error.",
    });
  }
);

// ============================================================
// START SERVER
// ============================================================

app.listen(
  PORT,
  () => {
    console.log(
      `BillX Backend running on port ${PORT}`
    );

    console.log(
      `Backend URL: ${PUBLIC_BASE_URL}`
    );

    console.log(
      "License system: READY"
    );
  }
);