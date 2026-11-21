package com.vaionyx.payroll;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.crypto.bcrypt.BCrypt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final JdbcTemplate jdbcTemplate;

    public AuthController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        if (request.email() == null || request.password() == null || request.email().isBlank() || request.password().isBlank()) {
            return ResponseEntity.badRequest().body(new ErrorResponse("Email and password are required."));
        }

        List<AppUser> users = jdbcTemplate.query(
                "select id, email, password_hash, role, is_active from public.users where lower(email) = lower(?)",
                userRowMapper(), request.email().trim());

        if (users.size() != 1 || !users.getFirst().active() || !BCrypt.checkpw(request.password(), users.getFirst().passwordHash())) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(new ErrorResponse("Invalid email or password."));
        }

        AppUser user = users.getFirst();
        jdbcTemplate.update("update public.users set last_login_at = ? where id = ?", Instant.now(), user.id());
        return ResponseEntity.ok(new LoginResponse(user.id().toString(), user.email(), user.role()));
    }

    private RowMapper<AppUser> userRowMapper() {
        return (ResultSet rs, int rowNum) -> new AppUser(
                rs.getObject("id", java.util.UUID.class),
                rs.getString("email"),
                rs.getString("password_hash"),
                rs.getString("role"),
                rs.getBoolean("is_active"));
    }

    public record LoginRequest(String email, String password) { }
    public record LoginResponse(String id, String email, String role) { }
    public record ErrorResponse(String message) { }
    private record AppUser(java.util.UUID id, String email, String passwordHash, String role, boolean active) { }
}
